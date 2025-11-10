require "kemal"
require "kemal-session"
require "db"
require "pg"
require "./db/setup"
require "./models/user"
require "csv" # For CSV validation

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

  if file.nil?
    next env.redirect "/upload?msg=No+file+selected"
  end

  # Read the uploaded file
  csv_content = File.read(file.tempfile.path)
  rows = CSV.parse(csv_content)

  if rows.empty?
    next env.redirect "/upload?msg=Empty+CSV+file"
  end

  total_rows = rows.size
  total_columns = rows.first.size
  missing_cells = rows.flatten.count { |v| v.strip.empty? }

  missing_ratio = missing_cells / (total_rows * total_columns).to_f
  score = ((1 - missing_ratio) * 100).round(2)

  <<-HTML
  <h1>Dataset Analysis Results</h1>
  <p><strong>Rows:</strong> #{total_rows}</p>
  <p><strong>Columns:</strong> #{total_columns}</p>
  <p><strong>Missing Values:</strong> #{missing_cells}</p>
  <p><strong>Validation Score:</strong> #{score}%</p>
  HTML
end



# Logout
get "/logout" do |env|
  env.session.destroy
  env.redirect "/login?msg=Logged+out"
end

puts "🚀 Server running at http://localhost:3000"
Kemal.run
