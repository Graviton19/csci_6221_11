module SyntheticDetector
  struct Stats
    property min : Float64
    property max : Float64
    property mean : Float64
    property std : Float64
    property unique_ratio : Float64
    property range_ratio : Float64

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
  # Compute statistics
  # ------------------------------------------------------
  def self.stats(values : Array(Float64)) : Stats
    return Stats.new(0, 0, 0, 0, 0, 0) if values.empty?

    min  = values.min
    max  = values.max
    mean = values.sum / values.size

    variance = values.map { |v| (v - mean)**2 }.sum / values.size
    std = Math.sqrt(variance)

    unique_ratio = values.uniq.size.to_f / values.size
    range_ratio = max == 0 ? 0.0 : (max - min).abs / max.abs

    Stats.new(min, max, mean, std, unique_ratio, range_ratio)
  end

  # ------------------------------------------------------
  # MAIN SYNTHETIC ANALYZER
  # ------------------------------------------------------
  def self.analyze(rows : Array(Hash(String, Float64)))
    return {100.0, ["Empty dataset"]} if rows.empty?

    # Extract all columns safely
    columns = rows.flat_map(&.keys).uniq

    # Build per-column arrays safely (fix for missing keys)
    column_data = Hash(String, Array(Float64)).new
    columns.each { |col| column_data[col] = [] of Float64 }

    rows.each do |row|
      columns.each do |col|
        if v = row[col]?
          column_data[col] << v
        end
      end
    end

    issues = [] of String
    synthetic_score = 0.0

    # -------- Compute stats for each column ----------
    stats_for = {} of String => Stats
    columns.each do |col|
      stats_for[col] = stats(column_data[col])
    end

    # ----------------------------------------------------
    # 1. Range + Variance Checks
    # ----------------------------------------------------
    columns.each do |col|
      s = stats_for[col]

      if s.range_ratio > 1_000_000
        issues << "Column '#{col}' has impossible value range"
        synthetic_score += 15
      end

      if s.std == 0
        issues << "Column '#{col}' has zero variance (identical values)"
        synthetic_score += 10
      end
    end

    # ----------------------------------------------------
    # 2. Uniqueness Checks
    # ----------------------------------------------------
    columns.each do |col|
      s = stats_for[col]

      if s.unique_ratio < 0.01
        issues << "Column '#{col}' has too few unique values"
        synthetic_score += 10
      end

      if s.unique_ratio > 0.95
        issues << "Column '#{col}' looks perfectly random"
        synthetic_score += 10
      end
    end

    # ----------------------------------------------------
    # 3. Correlation Checks
    # ----------------------------------------------------
    corr_values = [] of Float64

    columns.combinations(2).each do |(a, b)|
      corr = pearson(column_data[a], column_data[b])
      corr_values << corr.abs
    end

    if !corr_values.empty?
      if corr_values.all? { |c| c < 0.01 }
        issues << "All columns are fully independent (synthetic-like)"
        synthetic_score += 20
      end

      if corr_values.all? { |c| c > 0.98 }
        issues << "All columns are perfectly correlated (synthetic pattern)"
        synthetic_score += 20
      end
    end

    # ----------------------------------------------------
    # 4. Duplicate Row Detection
    # ----------------------------------------------------
    unique_rows = rows.uniq.size
    dupe_ratio = (rows.size - unique_rows).to_f / rows.size

    if dupe_ratio > 0.3
      issues << "More than 30% of rows are duplicated"
      synthetic_score += 20
    end

    # ----------------------------------------------------
    # 5. Stronger synthetic scoring
    # ----------------------------------------------------
    base = synthetic_score

    # Avg correlation score
    if !corr_values.empty?
      avg_corr = corr_values.sum / corr_values.size

      base += 25 if avg_corr < 0.05
      base += 10 if avg_corr < 0.15
    end

    # Random/uniform patterns
    columns.each do |col|
      s = stats_for[col]

      if s.unique_ratio > 0.98 && s.std > 0
        base += 15
      end

      if s.range_ratio > 0.8 && s.unique_ratio > 0.9
        base += 20
      end
    end

    # Based on number of issues
    base += 15 if issues.size >= 4
    base += 5 if issues.size >= 2

    final_score = base.clamp(0.0, 100.0)

    {final_score, issues}
  end

  # ------------------------------------------------------
  # Pearson correlation
  # ------------------------------------------------------
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
