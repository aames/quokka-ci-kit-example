// Package main is a small HTTP service that records quokka sightings on
// Rottnest Island.
//
//	GET  /sightings  lists every sighting, newest first
//	POST /sightings  records one: {"where":"Thomson Bay","count":2}
//
// It stores sightings in Postgres (ROTTNEST_DATABASE_URL) and creates its one
// table when the table is absent.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Sighting is one record: where the quokkas were seen and how many.
type Sighting struct {
	ID      int64     `json:"id"`
	Where   string    `json:"where"`
	Count   int       `json:"count"`
	Created time.Time `json:"created"`
}

// Store keeps sightings.
type Store interface {
	Add(ctx context.Context, where string, count int) (Sighting, error)
	List(ctx context.Context) ([]Sighting, error)
}

// maxWhere bounds the place name, in characters.
const maxWhere = 100

// maxCount bounds one sighting's count; a bigger number is a typo.
const maxCount = 1000

// errInvalid is a request the service refuses.
var errInvalid = errors.New("invalid sighting")

// validate trims and checks a sighting's fields.
func validate(where string, count int) (string, error) {
	where = strings.TrimSpace(where)
	if where == "" || len([]rune(where)) > maxWhere {
		return "", errInvalid
	}
	if count < 1 || count > maxCount {
		return "", errInvalid
	}
	return where, nil
}

// Handler serves /sightings over a store.
func Handler(s Store) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /sightings", func(w http.ResponseWriter, r *http.Request) {
		list, err := s.List(r.Context())
		if err != nil {
			writeError(w, http.StatusInternalServerError, "The sightings could not be read.")
			return
		}
		writeJSON(w, http.StatusOK, list)
	})
	mux.HandleFunc("POST /sightings", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Where string `json:"where"`
			Count int    `json:"count"`
		}
		dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
		dec.DisallowUnknownFields()
		if err := dec.Decode(&body); err != nil {
			writeError(w, http.StatusBadRequest, "Send a JSON body like {\"where\":\"Thomson Bay\",\"count\":2}.")
			return
		}
		where, err := validate(body.Where, body.Count)
		if err != nil {
			writeError(w, http.StatusBadRequest, "Give a place of up to 100 characters and a count from 1 to 1000.")
			return
		}
		got, err := s.Add(r.Context(), where, body.Count)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "The sighting could not be saved.")
			return
		}
		writeJSON(w, http.StatusCreated, got)
	})
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	return mux
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// MemoryStore is a Store in memory, for tests and a quick local look.
type MemoryStore struct {
	mu   sync.Mutex
	next int64
	all  []Sighting
	now  func() time.Time
}

// NewMemoryStore returns an empty MemoryStore.
func NewMemoryStore() *MemoryStore { return &MemoryStore{now: time.Now} }

// Add records a sighting.
func (m *MemoryStore) Add(_ context.Context, where string, count int) (Sighting, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.next++
	s := Sighting{ID: m.next, Where: where, Count: count, Created: m.now().UTC()}
	m.all = append(m.all, s)
	return s, nil
}

// List returns every sighting, newest first.
func (m *MemoryStore) List(_ context.Context) ([]Sighting, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]Sighting, 0, len(m.all))
	for i := len(m.all) - 1; i >= 0; i-- {
		out = append(out, m.all[i])
	}
	return out, nil
}
