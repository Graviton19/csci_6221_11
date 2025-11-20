require "kemal"
require "kemal-session"
require "db"
require "pg"
require "./db/setup"
require "./models/user"
require "csv"
require "digest/sha256"
require "./blockchain"
require "./synthetic_detector"
require "dotenv"
Dotenv.load

bc = Blockchain.new

Kemal::Session.config do |config|
  config.secret = ENV["SESSION_SECRET"]
  config.cookie_name = ENV["SESSION_KEY"]
end

Kemal.config do |config|
  config.public_folder = "public"
end


get "/login" do |env|
  render "src/views/login.ecr"
end


get "/register" do |env|
  error   = env.params.query["error"]?
  success = env.params.query["success"]?
  render "src/views/register.ecr"
end


post "/login" do |env|
  username = env.params.body["username"]?
  password = env.params.body["password"]?

  if username && password && User.authenticate(username, password)
    env.session.string("username", username)
    env.redirect "/"
  else
    env.redirect "/login?msg=Invalid+credentials"
  end
end

post "/register" do |env|
  username = env.params.body["username"]?
  password = env.params.body["password"]?
  confirm  = env.params.body["confirm_password"]?

  if username.nil? || password.nil? || confirm.nil?
    env.redirect "/register?error=Missing+fields"
    next
  end

  if password != confirm
    env.redirect "/register?error=Passwords+do+not+match"
    next
  end
  
  if User.exists?(username)
    env.redirect "/register?error=Username+already+taken"
    next
  end

  User.create(username, password)
  env.redirect "/login"
end



get "/" do |env|
  username = env.session.string?("username")
  if username
     render "src/views/dashboard.ecr"
  else
    env.redirect "/login"
  end
end

get "/upload" do |env|
  username = env.session.string?("username")
  if username
     render "src/views/upload.ecr"
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
  numeric_rows = [] of Hash(String, Float64)

  csv.each do |row|
    row_count += 1
    numeric_entry = {} of String => Float64

    headers.each do |key|
      val = (row[key]? || "").to_s
      missing_values += 1 if val.strip.empty?

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

      if val =~ /^\d+(\.\d+)?$/
        numeric_entry[key] = val.to_f64
      end
    end

    numeric_rows << numeric_entry unless numeric_entry.empty?
  end

  total_cells = row_count * column_count
  missing_ratio = total_cells == 0 ? 0.0 : missing_values.to_f / total_cells
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

  synth_score = 0.0
  synth_issues = [] of String

  begin
    synth_score, synth_issues = SyntheticDetector.analyze(numeric_rows)
  rescue e
    synth_issues << "Synthetic detection failed: #{e.message}"
  end

  hash_value = ""
  saved_to_blockchain = false
  dataset_message = ""
  owner_username = env.session.string?("username").to_s

  if synth_score < 75.0
    hash_value = Digest::SHA256.hexdigest(metadata)

    block, newly_added = bc.add_dataset(hash_value, owner_username)

    if newly_added
      saved_to_blockchain = true
      dataset_message = "Dataset successfully saved to blockchain."
    else
      dataset_message = "Dataset already in blockchain. Owner: #{block.owner}"
    end
  else
    hash_value = "Not generated dataset too synthetic (>75%)"
    dataset_message = "Dataset too synthetic, not saved."
  end

  html = String.build do |s|
    s << "<!DOCTYPE html><html><head><title>Dataset Analysis Results</title>"
    s << "<style>body{font-family:Arial;margin:25px;}.good{color:green;}.bad{color:red;font-weight:bold;}</style></head><body>"

    s << "<h1>Dataset Analysis Results</h1>"
    s << "<p><strong>Rows:</strong> #{row_count}</p>"
    s << "<p><strong>Columns:</strong> #{column_count}</p>"
    s << "<p><strong>Missing Ratio:</strong> #{missing_ratio}</p>"
    s << "<p><strong>Validation Score:</strong> #{score}%</p>"

    s << "<h2>Synthetic Data Check</h2>"
    s << "<p><strong>Synthetic Likelihood:</strong> #{synth_score}%</p>"

    if synth_score > 75.0
      s << "<p class='bad'>The dataset appears too synthetic and cannot be added to the blockchain.</p>"
    else
      s << "<p class='good'>Dataset looks valid for blockchain storage.</p>"
    end

    s << "<h2>Blockchain Result</h2>"
    s << "<p><strong>Hash:</strong> #{hash_value}</p>"
    s << "<p class='#{saved_to_blockchain ? "good" : "bad"}'>#{dataset_message}</p>"

    s << "<h2>Data Anomalies</h2>"
    if synth_issues.empty?
      s << "<p class='good'>No anomalies detected.</p>"
    else
      s << "<ul>"
      synth_issues.each do |issue|
        s << "<li>#{issue}</li>"
      end
      s << "</ul>"
    end

    s << "</body></html>"
  end

  env.response.content_type = "text/html"
  env.response.print html
end

get "/logout" do |env|
  env.session.destroy
  env.redirect "/login?msg=Logged+out"
end

puts "Server running at http://localhost:3000"
Kemal.run
