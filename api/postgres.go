package main

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgresStore is a Store in Postgres.
type PostgresStore struct{ pool *pgxpool.Pool }

// schema is the service's one table, created when absent.
const schema = `CREATE TABLE IF NOT EXISTS sightings (
	id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	place      text        NOT NULL CHECK (length(place) BETWEEN 1 AND 100),
	quokkas    integer     NOT NULL CHECK (quokkas BETWEEN 1 AND 1000),
	created_at timestamptz NOT NULL DEFAULT now()
)`

// OpenPostgres connects to url and makes sure the table exists.
func OpenPostgres(ctx context.Context, url string) (*PostgresStore, error) {
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, err
	}
	if _, err := pool.Exec(ctx, schema); err != nil {
		pool.Close()
		return nil, err
	}
	return &PostgresStore{pool: pool}, nil
}

// Close releases the connections.
func (p *PostgresStore) Close() { p.pool.Close() }

// Add records a sighting.
func (p *PostgresStore) Add(ctx context.Context, where string, count int) (Sighting, error) {
	s := Sighting{Where: where, Count: count}
	err := p.pool.QueryRow(ctx,
		`INSERT INTO sightings (place, quokkas) VALUES ($1, $2) RETURNING id, created_at`,
		where, count).Scan(&s.ID, &s.Created)
	return s, err
}

// List returns every sighting, newest first.
func (p *PostgresStore) List(ctx context.Context) ([]Sighting, error) {
	rows, err := p.pool.Query(ctx,
		`SELECT id, place, quokkas, created_at FROM sightings ORDER BY created_at DESC, id DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Sighting{}
	for rows.Next() {
		var s Sighting
		if err := rows.Scan(&s.ID, &s.Where, &s.Count, &s.Created); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}
