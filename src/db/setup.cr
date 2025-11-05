require "pg"
require "db"

DB_URL = "postgres://postgres:aalekh@localhost:5432/crystal_auth"

DB.open DB_URL do |db|
  db.exec <<-SQL
  CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL
  );
  SQL
end
