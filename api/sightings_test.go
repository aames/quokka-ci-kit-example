package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func do(t *testing.T, h http.Handler, method, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, "/sightings", strings.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestPostThenList(t *testing.T) {
	h := Handler(NewMemoryStore())
	rec := do(t, h, http.MethodPost, `{"where":"  Thomson Bay ","count":2}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("POST status %d, body %s", rec.Code, rec.Body)
	}
	var got Sighting
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Where != "Thomson Bay" || got.Count != 2 || got.ID != 1 {
		t.Fatalf("recorded %+v", got)
	}
	do(t, h, http.MethodPost, `{"where":"The Basin","count":5}`)
	rec = do(t, h, http.MethodGet, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("GET status %d", rec.Code)
	}
	var list []Sighting
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
		t.Fatal(err)
	}
	if len(list) != 2 || list[0].Where != "The Basin" || list[1].Where != "Thomson Bay" {
		t.Fatalf("listed %+v", list)
	}
}

func TestListEmptyIsAnArray(t *testing.T) {
	rec := do(t, Handler(NewMemoryStore()), http.MethodGet, "")
	if got := strings.TrimSpace(rec.Body.String()); got != "[]" {
		t.Fatalf("empty list is %q", got)
	}
}

func TestPostRefusals(t *testing.T) {
	cases := map[string]string{
		"not json":      `quokka`,
		"no place":      `{"where":"","count":1}`,
		"blank place":   `{"where":"   ","count":1}`,
		"zero":          `{"where":"Geordie Bay","count":0}`,
		"negative":      `{"where":"Geordie Bay","count":-3}`,
		"too many":      `{"where":"Geordie Bay","count":1001}`,
		"long place":    `{"where":"` + strings.Repeat("a", 101) + `","count":1}`,
		"unknown field": `{"where":"Geordie Bay","count":1,"colour":"brown"}`,
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			rec := do(t, Handler(NewMemoryStore()), http.MethodPost, body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status %d, body %s", rec.Code, rec.Body)
			}
		})
	}
}

type brokenStore struct{}

func (brokenStore) Add(context.Context, string, int) (Sighting, error) {
	return Sighting{}, errors.New("down")
}
func (brokenStore) List(context.Context) ([]Sighting, error) { return nil, errors.New("down") }

func TestStoreFailureIs500(t *testing.T) {
	h := Handler(brokenStore{})
	if rec := do(t, h, http.MethodGet, ""); rec.Code != http.StatusInternalServerError {
		t.Fatalf("GET status %d", rec.Code)
	}
	if rec := do(t, h, http.MethodPost, `{"where":"Parker Point","count":1}`); rec.Code != http.StatusInternalServerError {
		t.Fatalf("POST status %d", rec.Code)
	}
}

func TestMemoryStoreTimesAreUTC(t *testing.T) {
	m := NewMemoryStore()
	m.now = func() time.Time { return time.Date(2026, 11, 3, 9, 0, 0, 0, time.FixedZone("AWST", 8*3600)) }
	s, _ := m.Add(context.Background(), "Salmon Bay", 1)
	if s.Created.Location() != time.UTC || s.Created.Hour() != 1 {
		t.Fatalf("created %v", s.Created)
	}
}
