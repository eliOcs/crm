# Universal Search Feature

## Overview

Hybrid search implementation for the CRM to search across contacts, companies, tasks, and emails. Combines keyword-based full-text search (FTS5) with semantic vector search for accurate results.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Search Query                          │
└─────────────────────┬───────────────────────────────────┘
                      │
        ┌─────────────┴─────────────┐
        ▼                           ▼
┌───────────────────┐     ┌───────────────────┐
│  SQLite FTS5      │     │  sqlite-vec       │
│  (BM25 ranking)   │     │  (vector search)  │
└────────┬──────────┘     └────────┬──────────┘
         │                         │
         └──────────┬──────────────┘
                    ▼
         ┌───────────────────┐
         │ Reciprocal Rank   │
         │ Fusion (RRF)      │
         └─────────┬─────────┘
                   ▼
              Final Results
```

## Why Hybrid Search?

| Approach | Strengths | Weaknesses |
|----------|-----------|------------|
| **FTS5 (BM25)** | Exact matches, speed, transparency | Misses rephrased queries, no synonyms |
| **Vector Search** | Semantic understanding, synonyms, multilingual | Computationally expensive, "black box" |
| **Hybrid** | Best of both worlds | More complex to implement |

### When Each Approach Wins

**FTS5 is better for:**
- Exact phrase matching ("invoice 2024-001")
- Structured queries (email addresses, phone numbers)
- Speed-critical searches

**Vector search is better for:**
- Natural language queries ("emails about delayed shipments")
- Finding conceptually similar content
- Cross-language search

## Technology Stack

### Gems

```ruby
# Gemfile
gem "sqlite-vec"           # Vector search SQLite extension
gem "neighbor"             # Rails integration for vector search (KNN queries)
gem "voyageai"             # Embeddings API (Anthropic's recommended provider)
```

### Why These Choices?

| Component | Purpose | Rationale |
|-----------|---------|-----------|
| **FTS5** | Keyword search | Built into SQLite, battle-tested, zero infra |
| **sqlite-vec** | Vector similarity | Pure C, no dependencies, runs anywhere SQLite runs |
| **neighbor** | Rails integration | Makes KNN queries feel like ActiveRecord scopes |
| **Voyage AI** | Embeddings | Anthropic's partner, state-of-the-art models |

### Voyage AI Models

| Model | Dimensions | Use Case |
|-------|------------|----------|
| `voyage-3-large` | 1024 (default) | Highest quality |
| `voyage-3.5-lite` | 512-1024 | Fast, cost-effective |
| `voyage-code-3` | 1024 | Code search |

Pricing: ~$0.06 per 1M tokens (voyage-3-lite)

## Implementation Plan

### Phase 1: FTS5 Full-Text Search

Basic keyword search with BM25 ranking. No external dependencies.

#### Migration

```ruby
class CreateSearchIndex < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE search_index USING fts5(
        searchable_type,
        searchable_id UNINDEXED,
        title,
        content,
        tokenize='porter unicode61'
      );
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS search_index"
  end
end
```

#### Indexing Records

```ruby
class SearchIndexer
  def self.index(record)
    content = case record
    when Contact
      [record.name, record.email, record.job_role, record.department].compact.join(" ")
    when Company
      [record.legal_name, record.commercial_name, record.domain, record.location].compact.join(" ")
    when Email
      [record.subject, record.from, record.body_text].compact.join(" ")
    end

    execute_sql(<<~SQL, record.class.name, record.id, record.display_name, content)
      INSERT INTO search_index (searchable_type, searchable_id, title, content)
      VALUES (?, ?, ?, ?)
    SQL
  end
end
```

#### Querying

```ruby
class FtsSearch
  def self.search(query, limit: 20)
    sql = <<~SQL
      SELECT searchable_type, searchable_id, bm25(search_index) as score
      FROM search_index
      WHERE search_index MATCH ?
      ORDER BY score
      LIMIT ?
    SQL

    results = ActiveRecord::Base.connection.execute(sql, [query, limit])
    hydrate_results(results)
  end

  private

  def self.hydrate_results(results)
    results.group_by { |r| r["searchable_type"] }.flat_map do |type, records|
      type.constantize.where(id: records.map { |r| r["searchable_id"] })
    end
  end
end
```

### Phase 2: Vector Search

Add semantic search capabilities using embeddings.

#### Migration

```ruby
class CreateSearchEmbeddings < ActiveRecord::Migration[8.0]
  def change
    create_table :search_embeddings do |t|
      t.references :searchable, polymorphic: true, null: false
      t.binary :embedding, null: false  # 1024 floats = ~4KB
      t.timestamps
    end

    add_index :search_embeddings, [:searchable_type, :searchable_id], unique: true
  end
end
```

#### Model

```ruby
class SearchEmbedding < ApplicationRecord
  has_neighbors :embedding, dimensions: 1024

  belongs_to :searchable, polymorphic: true
end
```

#### Generating Embeddings

```ruby
class EmbeddingService
  def initialize
    @client = VoyageAI::Client.new(api_key: ENV["VOYAGE_API_KEY"])
  end

  def embed(text)
    response = @client.embed(
      input: text,
      model: "voyage-3-lite",
      input_type: "document"
    )
    response.embeddings.first
  end

  def embed_query(text)
    response = @client.embed(
      input: text,
      model: "voyage-3-lite",
      input_type: "query"
    )
    response.embeddings.first
  end
end
```

#### Vector Search

```ruby
class VectorSearch
  def self.search(query, limit: 20)
    embedding = EmbeddingService.new.embed_query(query)

    SearchEmbedding
      .nearest_neighbors(:embedding, embedding, distance: "cosine")
      .limit(limit)
      .includes(:searchable)
      .map(&:searchable)
  end
end
```

### Phase 3: Hybrid Search with RRF

Combine both approaches using Reciprocal Rank Fusion.

```ruby
class UniversalSearch
  def initialize(user)
    @user = user
  end

  def search(query, limit: 20)
    # Run both searches (could be parallelized with futures)
    fts_results = FtsSearch.search(query, limit: limit * 2)
    vec_results = VectorSearch.search(query, limit: limit * 2)

    # Combine with Reciprocal Rank Fusion
    combined = reciprocal_rank_fusion(fts_results, vec_results, k: 60)

    # Filter by user ownership and return top results
    combined.select { |r| r.user_id == @user.id }.first(limit)
  end

  private

  def reciprocal_rank_fusion(list_a, list_b, k: 60)
    scores = Hash.new(0)
    items = {}

    list_a.each_with_index do |item, rank|
      key = [item.class.name, item.id]
      scores[key] += 1.0 / (k + rank + 1)
      items[key] = item
    end

    list_b.each_with_index do |item, rank|
      key = [item.class.name, item.id]
      scores[key] += 1.0 / (k + rank + 1)
      items[key] = item
    end

    # Sort by combined score (descending) and return items
    scores.sort_by { |_, score| -score }.map { |key, _| items[key] }
  end
end
```

## Environment Variables

```bash
VOYAGE_API_KEY=pa-...  # Required for Phase 2+ (vector search)
```

## Cost Estimates

| Component | Cost |
|-----------|------|
| FTS5 | Free (built into SQLite) |
| sqlite-vec | Free (open source) |
| Voyage AI embeddings | ~$0.06 per 1M tokens |
| Storage per record | ~4KB (1024 floats) |

For a CRM with ~10,000 records: negligible cost.

## References

- [Hybrid full-text and vector search with SQLite](https://alexgarcia.xyz/blog/2024/sqlite-vec-hybrid-search/index.html)
- [Vector search with Rails and SQLite](https://www.teloslabs.co/post/vector-search-with-rails-and-sqlite)
- [Full-text search with Rails and SQLite](https://www.teloslabs.co/post/full-text-search-with-rails-and-sqlite)
- [sqlite-vec documentation](https://alexgarcia.xyz/sqlite-vec/)
- [Voyage AI embeddings](https://docs.voyageai.com/docs/embeddings)
- [Anthropic embeddings guide](https://docs.anthropic.com/claude/docs/embeddings)
- [neighbor gem](https://github.com/ankane/neighbor)
