module SyntheticDetector
  struct Stats
    property min : Float64
    property max : Float64
    property mean : Float64
    property std : Float64
    property unique_ratio : Float64
    property range_ratio : Float64

    # Crystal requires explicit initialization
    def initialize(
      @min : Float64,
      @max : Float64,
      @mean : Float64,
      @std : Float64,
      @unique_ratio : Float64,
      @range_ratio : Float64
    )
    end
  end

  # ------------------------------------------------------
  # Compute statistics for a numeric column
  # ------------------------------------------------------
  def self.stats(values : Array(Float64)) : Stats
    return Stats.new(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) if values.empty?

    min  = values.min
    max  = values.max
    mean = values.sum / values.size

    variance =
      values.map { |v| (v - mean) ** 2 }.sum / values.size
    std = Math.sqrt(variance)

    unique_ratio = values.uniq.size.to_f / values.size.to_f

    range_ratio = max == 0 ? 0.0 : ((max - min).abs / max.abs)

    Stats.new(min, max, mean, std, unique_ratio, range_ratio)
  end
  
  # ------------------------------------------------------
  # Main synthetic detector
  # Returns: { score (0–100), issues (Array(String)) }
  # ------------------------------------------------------
  def self.analyze(rows : Array(Hash(String, Float64)))
    return {100.0, ["Empty dataset"]} if rows.empty?

    columns = rows.first.keys
    issues = [] of String
    synthetic_score = 0.0

    # Build arrays for each column
    column_data = Hash(String, Array(Float64)).new
    columns.each { |col| column_data[col] = [] of Float64 }

    rows.each do |r|
      columns.each do |c|
        column_data[c] << r[c]
      end
    end

    # Cache stats per column (optimization + correctness)
    column_stats = {} of String => Stats
    columns.each { |col| column_stats[col] = stats(column_data[col]) }

    # -------------------------------
    # 1. Detect extreme/unreal ranges
    # -------------------------------
    columns.each do |col|
      s = column_stats[col]

      if s.range_ratio > 1_000_000
        issues << "Column '#{col}' has impossible range (very huge jump)"
        synthetic_score += 15
      end

      if s.std == 0
        issues << "Column '#{col}' has zero variance (all values identical)"
        synthetic_score += 10
      end
    end

    # -------------------------------
    # 2. Unique value check
    # -------------------------------
    columns.each do |col|
      s = column_stats[col]

      if s.unique_ratio < 0.01
        issues << "Column '#{col}' has too few unique values"
        synthetic_score += 10
      end

      if s.unique_ratio > 0.95
        issues << "Column '#{col}' looks perfectly random"
        synthetic_score += 10
      end
    end

    # -------------------------------
    # 3. Correlation check
    # -------------------------------
    corr_values = [] of Float64

    columns.combinations(2).each do |pair|
      a, b = pair
      corr = pearson(column_data[a], column_data[b])
      corr_values << corr.abs
    end

    if !corr_values.empty?
      if corr_values.all? { |c| c < 0.01 }
        issues << "Columns are fully independent — typical of synthetic data"
        synthetic_score += 20
      end

      if corr_values.all? { |c| c > 0.98 }
        issues << "Columns are perfectly correlated — synthetic pattern"
        synthetic_score += 20
      end
    end

    # -------------------------------
    # 4. Duplicate row detection
    # -------------------------------
    unique_rows = rows.uniq.size
    dupe_ratio = (rows.size - unique_rows).to_f / rows.size.to_f

    if dupe_ratio > 0.3
      issues << "More than 30% of rows are duplicated"
      synthetic_score += 20
    end

    synthetic_score = synthetic_score.clamp(0.0, 100.0)

    {synthetic_score, issues}
  end

  # Pearson correlation
  def self.pearson(a : Array(Float64), b : Array(Float64))
    return 0.0 if a.size != b.size || a.empty?

    mean_a = a.sum / a.size
    mean_b = b.sum / b.size

    num = 0.0
    den_a = 0.0
    den_b = 0.0

    a.size.times do |i|
      da = a[i] - mean_a
      db = b[i] - mean_b
      num += da * db
      den_a += da * da
      den_b += db * db
    end

    return 0.0 if den_a == 0 || den_b == 0

    num / Math.sqrt(den_a * den_b)
  end
end
