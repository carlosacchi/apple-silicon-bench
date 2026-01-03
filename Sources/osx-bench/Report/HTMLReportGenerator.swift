import Foundation

struct HTMLReportGenerator {
    let systemInfo: SystemInfo
    let results: BenchmarkResults
    let scores: BenchmarkScores

    /// Escape HTML special characters to prevent XSS
    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#x27;")
    }

    private func formatScoreHTML(_ score: Double) -> String {
        score > 0 ? String(Int(score)) : "<span style=\"color: #e74c3c;\">Failed</span>"
    }

    func generate() throws -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: results.timestamp)

        let fileName = "osx-bench-report-\(timestamp).html"

        // Save to Desktop for easy access
        let desktopDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/OSX-Bench-Reports")
        try FileManager.default.createDirectory(at: desktopDir, withIntermediateDirectories: true)

        let outputPath = desktopDir.appendingPathComponent(fileName)
        let html = generateHTML()

        try html.write(to: outputPath, atomically: true, encoding: .utf8)

        return outputPath.path
    }

    private func generateHTML() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .medium
        let formattedDate = dateFormatter.string(from: results.timestamp)

        let thermalWarning = results.hadAnyThrottling
            ? "<div class=\"thermal-warning\">⚠️ Thermal throttling detected during benchmark - results may be affected</div>"
            : ""

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>OSX-Bench Report - \(escapeHTML(systemInfo.chip))</title>
            <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js" integrity="sha384-9nhczxUqK87bcKHh20fSQcTGD4qq5GhayNYSYWqwBkINBhOfQLg/P5HG5lF1urn4" crossorigin="anonymous"></script>
            <style>
                :root {
                    --bg-primary: #1a1a2e;
                    --bg-secondary: #16213e;
                    --bg-card: #0f3460;
                    --text-primary: #eaeaea;
                    --text-secondary: #a0a0a0;
                    --accent: #e94560;
                    --accent-secondary: #00d9ff;
                    --success: #00ff88;
                    --warning: #feca57;
                }

                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }

                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', Roboto, sans-serif;
                    background: linear-gradient(135deg, var(--bg-primary) 0%, var(--bg-secondary) 100%);
                    color: var(--text-primary);
                    min-height: 100vh;
                    padding: 2rem;
                }

                .container {
                    max-width: 1200px;
                    margin: 0 auto;
                }

                header {
                    text-align: center;
                    margin-bottom: 3rem;
                }

                h1 {
                    font-size: 3rem;
                    font-weight: 700;
                    background: linear-gradient(90deg, var(--accent), var(--accent-secondary));
                    -webkit-background-clip: text;
                    -webkit-text-fill-color: transparent;
                    margin-bottom: 0.5rem;
                }

                .subtitle {
                    color: var(--text-secondary);
                    font-size: 1.1rem;
                }

                .system-info {
                    background: var(--bg-card);
                    border-radius: 16px;
                    padding: 2rem;
                    margin-bottom: 2rem;
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                    gap: 1.5rem;
                }

                .info-item {
                    text-align: center;
                }

                .info-label {
                    color: var(--text-secondary);
                    font-size: 0.85rem;
                    text-transform: uppercase;
                    letter-spacing: 1px;
                    margin-bottom: 0.5rem;
                }

                .info-value {
                    font-size: 1.4rem;
                    font-weight: 600;
                }

                .thermal-badge {
                    display: inline-flex;
                    align-items: center;
                    gap: 0.5rem;
                    padding: 0.25rem 0.75rem;
                    border-radius: 20px;
                    font-size: 0.9rem;
                }

                .thermal-nominal { background: rgba(0, 255, 136, 0.2); color: #00ff88; }
                .thermal-fair { background: rgba(254, 202, 87, 0.2); color: #feca57; }
                .thermal-serious { background: rgba(255, 159, 67, 0.2); color: #ff9f43; }
                .thermal-critical { background: rgba(233, 69, 96, 0.2); color: #e94560; }

                .thermal-warning {
                    background: rgba(254, 202, 87, 0.15);
                    border: 1px solid var(--warning);
                    color: var(--warning);
                    padding: 1rem;
                    border-radius: 12px;
                    margin-bottom: 2rem;
                    text-align: center;
                    font-weight: 500;
                }

                .scores-grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
                    gap: 1.5rem;
                    margin-bottom: 2rem;
                }

                .score-card {
                    background: var(--bg-card);
                    border-radius: 16px;
                    padding: 1.5rem;
                    text-align: center;
                    transition: transform 0.3s ease;
                }

                .score-card:hover {
                    transform: translateY(-5px);
                }

                .score-card.total {
                    grid-column: 1 / -1;
                    background: linear-gradient(135deg, var(--accent) 0%, #ff6b6b 100%);
                }

                .score-label {
                    color: var(--text-secondary);
                    font-size: 0.9rem;
                    margin-bottom: 0.5rem;
                }

                .total .score-label {
                    color: rgba(255,255,255,0.8);
                }

                .score-value {
                    font-size: 3rem;
                    font-weight: 700;
                }

                .total .score-value {
                    font-size: 4rem;
                }

                .benchmark-section {
                    background: var(--bg-card);
                    border-radius: 16px;
                    padding: 2rem;
                    margin-bottom: 2rem;
                }

                .benchmark-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: 1.5rem;
                }

                .benchmark-section h2 {
                    display: flex;
                    align-items: center;
                    gap: 0.5rem;
                }

                .benchmark-section h2::before {
                    content: '';
                    width: 4px;
                    height: 24px;
                    background: var(--accent);
                    border-radius: 2px;
                }

                .benchmark-thermal {
                    display: flex;
                    align-items: center;
                    gap: 0.5rem;
                    font-size: 0.85rem;
                    color: var(--text-secondary);
                }

                .test-grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                    gap: 1rem;
                }

                .test-item {
                    background: rgba(255,255,255,0.05);
                    border-radius: 12px;
                    padding: 1rem;
                }

                .test-name {
                    color: var(--text-secondary);
                    font-size: 0.85rem;
                    margin-bottom: 0.25rem;
                }

                .test-value {
                    font-size: 1.5rem;
                    font-weight: 600;
                    color: var(--accent-secondary);
                }

                .test-unit {
                    color: var(--text-secondary);
                    font-size: 0.85rem;
                }

                .chart-container {
                    height: 300px;
                    margin-top: 2rem;
                }

                .thermal-section {
                    background: var(--bg-card);
                    border-radius: 16px;
                    padding: 2rem;
                    margin-bottom: 2rem;
                }

                .thermal-timeline {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    padding: 1rem 0;
                }

                .thermal-point {
                    text-align: center;
                    flex: 1;
                }

                .thermal-emoji {
                    font-size: 2rem;
                    margin-bottom: 0.5rem;
                }

                .thermal-label {
                    font-size: 0.85rem;
                    color: var(--text-secondary);
                }

                footer {
                    text-align: center;
                    color: var(--text-secondary);
                    margin-top: 3rem;
                    padding-top: 2rem;
                    border-top: 1px solid rgba(255,255,255,0.1);
                }

                .apple-silicon-badge {
                    display: inline-block;
                    background: linear-gradient(90deg, #ff6b6b, #feca57, #48dbfb, #ff9ff3);
                    padding: 0.5rem 1rem;
                    border-radius: 20px;
                    font-weight: 600;
                    color: #1a1a2e;
                    margin-top: 1rem;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <header>
                    <h1>OSX-Bench</h1>
                    <p class="subtitle">Apple Silicon Performance Report</p>
                    <div class="apple-silicon-badge">\(escapeHTML(systemInfo.chip))</div>
                </header>

                \(thermalWarning)

                <section class="system-info">
                    <div class="info-item">
                        <div class="info-label">Chip</div>
                        <div class="info-value">\(escapeHTML(systemInfo.chip))</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">Cores</div>
                        <div class="info-value">\(systemInfo.coresPerformance)P + \(systemInfo.coresEfficiency)E</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">Memory</div>
                        <div class="info-value">\(systemInfo.ramGB) GB</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">macOS</div>
                        <div class="info-value">\(escapeHTML(systemInfo.osVersion))</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">Date</div>
                        <div class="info-value">\(escapeHTML(formattedDate))</div>
                    </div>
                </section>

                <section class="scores-grid">
                    <div class="score-card total">
                        <div class="score-label">Total Score</div>
                        <div class="score-value">\(formatScoreHTML(scores.total))</div>
                    </div>
                    \(scores.ranCpuSingle ? """
                    <div class="score-card">
                        <div class="score-label">CPU Single-Core</div>
                        <div class="score-value">\(formatScoreHTML(scores.cpuSingleCore))</div>
                    </div>
                    """ : "")
                    \(scores.ranCpuMulti ? """
                    <div class="score-card">
                        <div class="score-label">CPU Multi-Core</div>
                        <div class="score-value">\(formatScoreHTML(scores.cpuMultiCore))</div>
                    </div>
                    """ : "")
                    \(scores.ranMemory ? """
                    <div class="score-card">
                        <div class="score-label">Memory</div>
                        <div class="score-value">\(formatScoreHTML(scores.memory))</div>
                    </div>
                    """ : "")
                    \(scores.ranDisk ? """
                    <div class="score-card">
                        <div class="score-label">Disk</div>
                        <div class="score-value">\(formatScoreHTML(scores.disk))</div>
                    </div>
                    """ : "")
                    \(scores.ranGpu ? """
                    <div class="score-card">
                        <div class="score-label">GPU</div>
                        <div class="score-value">\(formatScoreHTML(scores.gpu))</div>
                    </div>
                    """ : "")
                </section>

                \(generateThermalSection())

                \(generateBenchmarkSections())

                <section class="benchmark-section">
                    <h2>Score Breakdown</h2>
                    <div class="chart-container">
                        <canvas id="scoresChart"></canvas>
                    </div>
                </section>

                <footer>
                    <p>Generated by \(AppInfo.fullName) v\(AppInfo.version)</p>
                    <p>Benchmark for Apple Silicon</p>
                </footer>
            </div>

            <script>
                const ctx = document.getElementById('scoresChart').getContext('2d');
                new Chart(ctx, {
                    type: 'bar',
                    data: {
                        labels: [\(generateChartLabels())],
                        datasets: [{
                            label: 'Score',
                            data: [\(generateChartData())],
                            backgroundColor: [\(generateChartColors(alpha: 0.8))],
                            borderColor: [\(generateChartColors(alpha: 1.0))],
                            borderWidth: 2,
                            borderRadius: 8
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        plugins: {
                            legend: {
                                display: false
                            }
                        },
                        scales: {
                            y: {
                                beginAtZero: true,
                                grid: {
                                    color: 'rgba(255,255,255,0.1)'
                                },
                                ticks: {
                                    color: '#a0a0a0'
                                }
                            },
                            x: {
                                grid: {
                                    display: false
                                },
                                ticks: {
                                    color: '#a0a0a0'
                                }
                            }
                        }
                    }
                });
            </script>
        </body>
        </html>
        """
    }

    private func generateAIScoreSection() -> String {
        // Get AI benchmark result for sub-scores
        guard let aiResult = results.result(for: .ai) else { return "" }
        let subScores = aiResult.tests.map { test -> String in
            """
            <div class="test-item">
                <div class="test-name">\(escapeHTML(test.name))</div>
                <div class="test-value">\(escapeHTML(test.formattedValue)) <span class="test-unit">\(escapeHTML(test.unit))</span></div>
            </div>
            """
        }.joined(separator: "\n")

        return """
        <section class="benchmark-section" style="background: linear-gradient(135deg, #2a2a4a 0%, #1a1a3a 100%); border: 2px solid #00CED1;">
            <div class="benchmark-header">
                <h2 style="color: #00CED1;">AI/ML Score (Separate)</h2>
            </div>
            <div style="text-align: center; margin-bottom: 1.5rem;">
                <div style="font-size: 4rem; font-weight: 700; color: #00CED1;">\(formatScoreHTML(scores.ai))</div>
                <div style="color: #a0a0a0; font-size: 0.9rem;">Neural Engine & CoreML Performance</div>
            </div>
            <div class="test-grid">
                \(subScores)
            </div>
            <p style="text-align: center; color: #a0a0a0; margin-top: 1rem; font-size: 0.85rem;">
                AI Score is separate from Total Score (like Geekbench AI)
            </p>
        </section>
        """
    }

    private func generateThermalSection() -> String {
        guard !results.thermalData.isEmpty else { return "" }

        let thermalPoints = results.benchmarks.map { result -> String in
            let emoji = result.thermalEnd.emoji
            let name = result.type.displayName.replacingOccurrences(of: " ", with: "<br>")
            return """
            <div class="thermal-point">
                <div class="thermal-emoji">\(emoji)</div>
                <div class="thermal-label">\(name)</div>
            </div>
            """
        }.joined(separator: "\n")

        return """
        <section class="thermal-section">
            <h2>Thermal Progression</h2>
            <div class="thermal-timeline">
                \(thermalPoints)
            </div>
            <p style="text-align: center; color: var(--text-secondary); margin-top: 1rem; font-size: 0.85rem;">
                🟢 Normal &nbsp; 🟡 Warm &nbsp; 🟠 Hot &nbsp; 🔴 Critical
            </p>
        </section>
        """
    }

    private func generateBenchmarkSections() -> String {
        var sections = ""

        for result in results.benchmarks {
            let thermalBadge = getThermalBadgeHTML(start: result.thermalStart, end: result.thermalEnd)

            sections += """
            <section class="benchmark-section">
                <div class="benchmark-header">
                    <h2>\(result.type.displayName)</h2>
                    <div class="benchmark-thermal">
                        \(thermalBadge)
                    </div>
                </div>
                <div class="test-grid">
                    \(result.tests.map { test in
                        """
                        <div class="test-item">
                            <div class="test-name">\(escapeHTML(test.name))</div>
                            <div class="test-value">\(escapeHTML(test.formattedValue)) <span class="test-unit">\(escapeHTML(test.unit))</span></div>
                        </div>
                        """
                    }.joined(separator: "\n"))
                </div>
            </section>
            """

            // Add AI score section right after AI benchmark
            if result.type == .ai {
                sections += generateAIScoreSection()
            }
        }

        return sections
    }

    private func getThermalBadgeHTML(start: ThermalMonitor.ThermalLevel, end: ThermalMonitor.ThermalLevel) -> String {
        let cssClass: String
        switch end {
        case .nominal: cssClass = "thermal-nominal"
        case .fair: cssClass = "thermal-fair"
        case .serious: cssClass = "thermal-serious"
        case .critical: cssClass = "thermal-critical"
        }

        if start == end {
            return "<span class=\"thermal-badge \(cssClass)\">\(end.emoji) \(end.rawValue)</span>"
        } else {
            return "<span class=\"thermal-badge \(cssClass)\">\(start.emoji) → \(end.emoji)</span>"
        }
    }

    // MARK: - Chart Helpers

    private func generateChartLabels() -> String {
        var labels: [String] = []
        if scores.ranCpuSingle { labels.append("'CPU Single'") }
        if scores.ranCpuMulti { labels.append("'CPU Multi'") }
        if scores.ranMemory { labels.append("'Memory'") }
        if scores.ranDisk { labels.append("'Disk'") }
        if scores.ranGpu { labels.append("'GPU'") }
        return labels.joined(separator: ", ")
    }

    private func generateChartData() -> String {
        var data: [String] = []
        if scores.ranCpuSingle { data.append(String(Int(scores.cpuSingleCore))) }
        if scores.ranCpuMulti { data.append(String(Int(scores.cpuMultiCore))) }
        if scores.ranMemory { data.append(String(Int(scores.memory))) }
        if scores.ranDisk { data.append(String(Int(scores.disk))) }
        if scores.ranGpu { data.append(String(Int(scores.gpu))) }
        return data.joined(separator: ", ")
    }

    private func generateChartColors(alpha: Double) -> String {
        let colors = [
            (r: 233, g: 69, b: 96),    // CPU Single - red
            (r: 0, g: 217, b: 255),    // CPU Multi - cyan
            (r: 0, g: 255, b: 136),    // Memory - green
            (r: 254, g: 202, b: 87),   // Disk - yellow
            (r: 155, g: 89, b: 182)    // GPU - purple
        ]
        var result: [String] = []
        if scores.ranCpuSingle { result.append(formatColor(colors[0], alpha: alpha)) }
        if scores.ranCpuMulti { result.append(formatColor(colors[1], alpha: alpha)) }
        if scores.ranMemory { result.append(formatColor(colors[2], alpha: alpha)) }
        if scores.ranDisk { result.append(formatColor(colors[3], alpha: alpha)) }
        if scores.ranGpu { result.append(formatColor(colors[4], alpha: alpha)) }
        return result.joined(separator: ", ")
    }

    private func formatColor(_ color: (r: Int, g: Int, b: Int), alpha: Double) -> String {
        "'rgba(\(color.r), \(color.g), \(color.b), \(alpha))'"
    }
}
