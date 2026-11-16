import Combine
import SwiftUI

/// The weather channel: the music from the schedule plays underneath while a
/// WeatherStar-style card set cycles through the forecast.
struct WeatherOverlay: View {
    let store: GuideStore

    @State private var pageIndex = 0
    @State private var rotation = Timer.publish(every: 11, on: .main, in: .common).autoconnect()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
        .onReceive(rotation) { _ in
            let count = pages.count
            guard count > 0 else { return }
            pageIndex = (pageIndex + 1) % count
        }
        .onChange(of: pages.count) { _, count in
            pageIndex = count == 0 ? 0 : pageIndex % count
        }
        .onAppear { pageIndex = 0 }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20 * 60))
                guard !Task.isCancelled else { return }
                await store.ensureWeather()
            }
        }
    }

    private func content(now: Date) -> some View {
        let allPages = pages
        let index = allPages.isEmpty ? 0 : pageIndex % allPages.count
        let page = allPages.isEmpty ? WeatherPage.placeholder : allPages[index]

        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.106, green: 0.247, blue: 0.659),
                    Color(red: 0.039, green: 0.110, blue: 0.420)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header(page.title, now: now)

                pageBody(page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.vertical, 26)

                footer(index: index, count: allPages.count)
            }
            .padding(.horizontal, 76)
            .padding(.top, 50)
            .padding(.bottom, 38)
        }
    }

    private func header(_ title: String, now: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.bw(38, .black))
                .foregroundStyle(BW.yellow)
            Spacer()
            Text(BW.time(now))
                .font(.bw(34, .black))
                .foregroundStyle(BW.orange)
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BW.orange).frame(height: 4)
        }
    }

    private func footer(index: Int, count: Int) -> some View {
        HStack {
            Text("PAGE \(index + 1) OF \(max(1, count))")
                .font(.bw(17, .black))
                .foregroundStyle(BW.orange)
            Spacer()
            Text("BACKWHENTV WEATHER")
                .font(.bw(17, .black))
                .foregroundStyle(BW.orange)
        }
    }

    @ViewBuilder
    private func pageBody(_ page: WeatherPage) -> some View {
        switch page.kind {
        case .current(let report):
            HStack(alignment: .top, spacing: 90) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(report.now.tempF))°")
                        .font(.bw(176, .black))
                        .foregroundStyle(BW.yellow)
                        .lineLimit(1)
                    Text(report.now.text.uppercased())
                        .font(.bw(48, .black))
                        .foregroundStyle(.white)
                    Text("\(report.city.uppercased()), \(report.state)")
                        .font(.bw(28, .bold))
                        .foregroundStyle(BW.ice)
                        .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 18) {
                    detail("WIND", wind(report))
                    detail("HUMIDITY", percent(report.now.humidity))
                    detail("PRESSURE", pressure(report.now.pressureIn))
                    detail("VISIBILITY", visibility(report.now.visibilityMi))
                    if let station = report.now.station {
                        detail("STATION", station.uppercased())
                    }
                }
                .padding(.top, 26)

                Spacer()
            }

        case .forecast(let periods):
            VStack(alignment: .leading, spacing: 26) {
                ForEach(periods) { period in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(period.name.uppercased())
                                .font(.bw(30, .black))
                                .foregroundStyle(BW.yellow)
                            if let temp = period.tempF {
                                Text("\(Int(temp))°")
                                    .font(.bw(30, .black))
                                    .foregroundStyle(.white)
                            }
                            if let short = period.short {
                                Text(short.uppercased())
                                    .font(.bw(22, .bold))
                                    .foregroundStyle(BW.ice)
                            }
                        }
                        if let detail = period.detail {
                            Text(detail)
                                .font(.bw(23, .regular))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }
                    }
                }
            }

        case .extended(let periods):
            VStack(spacing: 13) {
                ForEach(periods) { period in
                    HStack(spacing: 18) {
                        Text(period.name.uppercased())
                            .font(.bw(25, .black))
                            .foregroundStyle(BW.yellow)
                            .frame(width: 300, alignment: .leading)
                        Text((period.short ?? "").uppercased())
                            .font(.bw(22, .regular))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer()
                        if let temp = period.tempF {
                            Text("\(Int(temp))°")
                                .font(.bw(25, .black))
                                .foregroundStyle(BW.orange)
                                .frame(width: 90, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 18)
                    .background(Color.black.opacity(0.18))
                }
            }

        case .alerts(let alerts):
            VStack(alignment: .leading, spacing: 26) {
                ForEach(alerts.prefix(3)) { alert in
                    VStack(alignment: .leading, spacing: 8) {
                        Text((alert.event ?? "ALERT").uppercased())
                            .font(.bw(32, .black))
                            .foregroundStyle(BW.alert)
                        Text(alert.headline ?? "")
                            .font(.bw(24, .regular))
                            .foregroundStyle(.white)
                    }
                }
            }

        case .briefing(let briefing):
            VStack(alignment: .leading, spacing: 14) {
                if let office = briefing.office {
                    Text("NATIONAL WEATHER SERVICE · \(office.uppercased())")
                        .font(.bw(18, .black))
                        .foregroundStyle(BW.orange)
                }
                ScrollView {
                    Text(briefing.text ?? "")
                        .font(.bw(24, .regular))
                        .foregroundStyle(.white)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        case .radar(let url):
            VStack(spacing: 12) {
                RemoteImageView(url: url)
                    .frame(maxWidth: 1120, maxHeight: 520)
                    .overlay(Rectangle().stroke(BW.orange, lineWidth: 4))
                Text("REGIONAL RADAR LOOP")
                    .font(.bw(16, .black))
                    .foregroundStyle(BW.ice)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .placeholder:
            VStack(alignment: .leading, spacing: 14) {
                Text("GETTING THE FORECAST...")
                    .font(.bw(40, .black))
                    .foregroundStyle(BW.yellow)
                Text("WeatherStar 4000 is dialing up the National Weather Service.")
                    .font(.bw(24, .regular))
                    .foregroundStyle(BW.ice)
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(spacing: 18) {
            Text(label)
                .font(.bw(18, .black))
                .foregroundStyle(BW.yellow)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(.bw(24, .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Formatting

    private func wind(_ report: WeatherReport) -> String {
        let speed = report.now.windMph.map { "\(Int($0)) MPH" } ?? "—"
        return [report.now.windDir?.uppercased(), speed].compactMap { $0 }.joined(separator: " ")
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int($0))%" } ?? "—"
    }

    private func pressure(_ value: Double?) -> String {
        value.map { String(format: "%.2f IN", $0) } ?? "—"
    }

    private func visibility(_ value: Double?) -> String {
        value.map { String(format: "%.0f MI", $0) } ?? "—"
    }

    // MARK: - Pages

    private var pages: [WeatherPage] {
        guard let report = store.weather else {
            return [.placeholder]
        }

        var result: [WeatherPage] = [
            WeatherPage(title: "CURRENT CONDITIONS", kind: .current(report)),
            WeatherPage(title: "LOCAL FORECAST", kind: .forecast(Array(report.periods.prefix(3)))),
            WeatherPage(title: "EXTENDED FORECAST", kind: .extended(Array(report.periods.prefix(8))))
        ]

        if let extra = store.weatherExtra {
            if let alerts = extra.alerts, !alerts.isEmpty {
                result.append(WeatherPage(title: "WEATHER ALERTS", kind: .alerts(alerts)))
            } else if let briefing = extra.briefing, let text = briefing.text, !text.isEmpty {
                result.append(WeatherPage(title: briefing.title ?? "FORECAST DISCUSSION", kind: .briefing(briefing)))
            }
            if let still = extra.radar?.still, let url = URL(string: still) {
                result.append(WeatherPage(title: "REGIONAL RADAR", kind: .radar(url)))
            }
        }

        return result
    }
}

private struct WeatherPage {
    let title: String
    let kind: Kind

    enum Kind {
        case current(WeatherReport)
        case forecast([WeatherReport.Period])
        case extended([WeatherReport.Period])
        case alerts([WeatherExtra.Alert])
        case briefing(WeatherExtra.Briefing)
        case radar(URL)
        case placeholder
    }

    static let placeholder = WeatherPage(title: "LOCAL FORECAST", kind: .placeholder)
}
