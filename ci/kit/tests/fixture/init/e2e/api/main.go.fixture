package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	url := os.Getenv("ROTTNEST_DATABASE_URL")
	if url == "" {
		log.Fatal("ROTTNEST_DATABASE_URL is not set, so the service did not start.")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	store, err := OpenPostgres(ctx, url)
	cancel()
	if err != nil {
		log.Fatalf("the database could not be opened: %v", err)
	}
	defer store.Close()
	addr := os.Getenv("ROTTNEST_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	srv := &http.Server{Addr: addr, Handler: Handler(store), ReadHeaderTimeout: 5 * time.Second}
	log.Printf("listening on %s", addr)
	log.Fatal(srv.ListenAndServe())
}
