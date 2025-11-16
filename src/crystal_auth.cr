require "kemal"
require "kemal-session"
require "db"
require "pg"
require "./db/setup"
require "./models/user"
require "csv" # For CSV validation
require "digest/sha256"

# Session config
Kemal::Session.config do |config|
  config.secret = "aalekh_key_change_this"
  config.cookie_name = "crystal_auth_session"
end

# Serve static assets from src/public (Kemal will look relative to working dir)
Kemal.config do |config|
  config.public_folder = "public"
end

# Login page (GET)
get "/login" do |env|
  render "src/views/login.ecr"
end

# Register page (GET)
get "/register" do |env|
  render "src/views/register.ecr"
end


# GET upload page
get "/upload" do
  render "src/views/upload.ecr"
end

# Login POST
post "/login" do |env|
  username = env.params.body["username"]?
  password = env.params.body["password"]?

  if username && password && User.authenticate(username, password)
    # store username in session using kemal-session typed API
    env.session.string("username", username)
    env.redirect "/"
  else
    env.redirect "/login?msg=Invalid+credentials"
  end
end

# Register POST
post "/register" do |env|
  username = env.params.body["username"]?
  password = env.params.body["password"]?

  begin
    if username && password
      User.create(username, password)
      env.redirect "/login?msg=Account+created+successfully"
    else
      env.redirect "/register?msg=Missing+fields"
    end
  rescue e
    env.redirect "/register?msg=Registration+failed"
  end
end

# Dashboard (GET /)
get "/" do |env|
  # read username from session (may be nil)
  username = env.session.string?("username")
  if username
     render "src/views/dashboard.ecr"
  else
    env.redirect "/login"
  end
end


post "/upload" do |env|
  file = env.params.files["dataset"]?

  unless file
    env.redirect "/upload?msg=No+file+selected"
    next
  end

  csv_path = file.tempfile.path
  content = File.read(csv_path)
  csv = CSV.new(content, headers: true)

  headers = csv.headers
  column_count = headers.size

  row_count = 0
  missing_values = 0
  sample_types = Hash(String, String).new

  csv.each do |row|
    row_count += 1

    headers.each do |key|
      val = (row[key]? || "").to_s

      # Missing value check
      if val.strip.empty?
        missing_values += 1
      end

      # Infer type only once
      unless sample_types.has_key?(key)
        inferred =
          if val =~ /^\d+$/
            "Integer"
          elsif val =~ /^\d+\.\d+$/
            "Float"
          else
            "String"
          end

        sample_types[key] = inferred
      end
    end
  end

  total_cells = row_count * column_count
  missing_ratio = total_cells == 0 ? 0.0 : missing_values.to_f / total_cells

  # Score: 100 = perfect dataset, 0 = worse
  score = ((1.0 - missing_ratio) * 100).round(2)

  metadata = String.build do |s|
    s << "rows=#{row_count};"
    s << "columns=#{column_count};"
    s << "headers=#{headers.join(",")};"
    s << "missing_values=#{missing_values};"
    s << "missing_ratio=#{missing_ratio};"
    s << "validation_score=#{score};"

    sample_types.each do |col, type|
      s << "#{col}:#{type};"
    end
  end

  hash = Digest::SHA256.hexdigest(metadata)

  puts 
  puts metadata
  puts 
  puts hash

  # TODO → send `hash` to blockchain

  html = <<-HTML
    <h1>Dataset Analysis Results</h1>
    <p><strong>Rows:</strong> #{row_count}</p>
    <p><strong>Columns:</strong> #{column_count}</p>
    <p><strong>Missing Value Ratio:</strong> #{missing_ratio}</p>
    <p><strong>Validation Score:</strong> #{score}%</p>
    <p><strong>SHA256 Hash:</strong> #{hash}</p>
  HTML

  env.response.content_type = "text/html"
  env.response.print html
end



# Logout
get "/logout" do |env|
  env.session.destroy
  env.redirect "/login?msg=Logged+out"
end

puts "Server running at http://localhost:3000"
Kemal.run
