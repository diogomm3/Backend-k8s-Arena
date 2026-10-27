-- Backend-k8s-Arena database schema
-- Exact implementation of spec/API.md section 11
-- No additional indexes or constraints beyond what queries require

-- users
CREATE TABLE users (
  id serial PRIMARY KEY,
  username text UNIQUE NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- posts
CREATE TABLE posts (
  id serial PRIMARY KEY,
  user_id int NOT NULL REFERENCES users(id),
  content text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Feed index: (created_at DESC, id DESC) for /feed ordering
CREATE INDEX posts_created_at_id_desc ON posts (created_at DESC, id DESC);

-- likes: PK (post_id, user_id) IN THAT ORDER
CREATE TABLE likes (
  post_id int NOT NULL REFERENCES posts(id),
  user_id int NOT NULL REFERENCES users(id),
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);