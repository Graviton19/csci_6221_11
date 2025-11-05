require "pg"
require "db"
require "crypto/bcrypt"

class User
  def self.create(username : String, password : String)
    hashed = Crypto::Bcrypt::Password.create(password)
    DB.open(DB_URL) do |db|
      db.exec "INSERT INTO users (username, password) VALUES ($1, $2)", username, hashed.to_s
    end
  end

  def self.authenticate(username : String, password : String)
    DB.open(DB_URL) do |db|
      result = db.query_one?(
        "SELECT password FROM users WHERE username = $1", username,
        as: {String}
      )
      return false unless result
      stored_password = Crypto::Bcrypt::Password.new(result)
      stored_password.verify(password)
    end
  end
end
