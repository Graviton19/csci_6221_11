require "pg"
require "db"
require "dotenv"

Dotenv.load

DB_URL = ENV["DB_URL"]

DB.open DB_URL do |db|
  db.exec <<-SQL
  CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL
  );
  SQL
end
