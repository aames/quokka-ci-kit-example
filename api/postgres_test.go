package main

import (
	"context"
	"os"
	"testing"
	"time"
)

// TestPostgresStore runs against the database ROTTNEST_TEST_PG_URL names. The
// check's driver and CI both hand it a throwaway Postgres; with no URL the
// test fails rather than skips, so a job that lost its database cannot pass.
func TestPostgresStore(t *testing.T) {
	url := os.Getenv("ROTTNEST_TEST_PG_URL")
	if url == "" {
		t.Fatal("ROTTNEST_TEST_PG_URL is not set, so the Postgres store was not tested.")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	store, err := OpenPostgres(ctx, url)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer store.Close()
	if _, err := store.pool.Exec(ctx, `TRUNCATE sightings`); err != nil {
		t.Fatal(err)
	}
	// Opening twice is safe: the table is created only when absent.
	again, err := OpenPostgres(ctx, url)
	if err != nil {
		t.Fatalf("second open: %v", err)
	}
	again.Close()

	first, err := store.Add(ctx, "Thomson Bay", 2)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.Add(ctx, "Little Armstrong Bay", 4); err != nil {
		t.Fatal(err)
	}
	list, err := store.List(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 2 || list[0].Where != "Little Armstrong Bay" || list[1].ID != first.ID || list[1].Count != 2 {
		t.Fatalf("listed %+v", list)
	}
	// The table refuses what the handler refuses.
	if _, err := store.Add(ctx, "Pinky Beach", 0); err == nil {
		t.Fatal("a count of 0 was stored")
	}
}
