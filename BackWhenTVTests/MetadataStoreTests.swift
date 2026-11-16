import XCTest
@testable import BackWhenTV

@MainActor
final class MetadataStoreTests: XCTestCase {
    // MARK: - Title preparation

    func testEpisodeTitlesUseTheTVCategory() throws {
        let query = try XCTUnwrap(MetadataQuery(rawTitle: "GUMMI BEARS | S02E06 - THE CRIMSON AVENGER"))
        XCTAssertEqual(query.lookup.category, .tv)
        XCTAssertEqual(query.lookup.name, "GUMMI BEARS S02E06 - THE CRIMSON AVENGER")
    }

    func testOtherTitlesUseTheMovieCategory() throws {
        let query = try XCTUnwrap(MetadataQuery(rawTitle: "THE CARPENTERS A CHRISTMAS PORTRAIT | 1978"))
        XCTAssertEqual(query.lookup.category, .movies)
        XCTAssertEqual(query.lookup.name, "THE CARPENTERS A CHRISTMAS PORTRAIT 1978")
    }

    func testSchedulePrefixesAreRemoved() throws {
        let retro = try XCTUnwrap(MetadataQuery(rawTitle: "RETRO SHORT | Superman: The Mad Scientist (1941)"))
        XCTAssertEqual(retro.lookup.name, "Superman: The Mad Scientist (1941)")

        let rated = try XCTUnwrap(MetadataQuery(rawTitle: "C THE CARPENTERS A CHRISTMAS PORTRAIT | 1978"))
        XCTAssertEqual(rated.lookup.name, "THE CARPENTERS A CHRISTMAS PORTRAIT 1978")
    }

    func testCommercialsAndBlankTitlesAreSkipped() {
        XCTAssertNil(MetadataQuery(rawTitle: "COMMERCIAL BREAK | Station Micro Ident (5s)"))
        XCTAssertNil(MetadataQuery(rawTitle: "   "))
    }

    func testSimilarShowNamesAreNotMistakenForTheRetroShortLabel() throws {
        let query = try XCTUnwrap(MetadataQuery(rawTitle: "RETRO SHORTS Marathon"))
        XCTAssertEqual(query.lookup.name, "RETRO SHORTS Marathon")
    }

    // MARK: - Request building

    func testLookupRequestUsesTheBatchEndpointAndBearerToken() throws {
        let request = try OpenMetadataClient.makeLookupRequest(
            items: [MetadataLookup(category: .tv, name: "The Simpsons S01E01")],
            apiKey: "test-key"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://openmetadata.nexus/api/v1/lookup")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let items = try XCTUnwrap(json["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0]["category"] as? String, "tv")
        XCTAssertEqual(items[0]["name"] as? String, "The Simpsons S01E01")
    }

    // MARK: - Result filtering

    func testAcceptsResolvedAndConfidentUnresolvedOverviews() {
        XCTAssertEqual(makeResult(state: "resolved", overview: "Good").info?.overview, "Good")
        XCTAssertEqual(
            makeResult(state: "unresolved", overview: "Plausible", confidence: 0.46).info?.overview,
            "Plausible"
        )
        XCTAssertNil(makeResult(state: "unresolved", overview: "Wrong", confidence: 0).info)
        XCTAssertNil(makeResult(state: "pending", overview: "Not ready").info)
    }

    func testRefusalsAndEmptyOverviewsAreIgnored() {
        var refused = makeResult(state: "resolved", overview: "Nope")
        XCTAssertNotNil(refused.info)
        refused = makeResult(state: "resolved", overview: "Nope", refusal: "subtitle")
        XCTAssertNil(refused.info)
        XCTAssertNil(makeResult(state: "resolved", overview: "   ").info)
    }

    // MARK: - Queue

    func testOverviewIsStoredAfterABatch() async throws {
        let item = MetadataLookup(category: .tv, name: "The Simpsons S01E01")
        let store = MetadataStore(lookup: { requested in
            XCTAssertEqual(requested, [item])
            return [self.makeResult(state: "resolved", overview: "Homer's Christmas bonus is canceled.")]
        })

        store.enqueue(titles: ["The Simpsons S01E01"])
        await waitUntilIdle(store)

        XCTAssertEqual(
            store.overview(forTitle: "The Simpsons S01E01")?.overview,
            "Homer's Christmas bonus is canceled."
        )
    }

    func testLowConfidenceMissIsNotRetried() async throws {
        var calls = 0
        let store = MetadataStore(lookup: { _ in
            calls += 1
            return [self.makeResult(state: "unresolved", overview: "Wrong show", confidence: 0)]
        })

        store.enqueue(titles: ["The Godfather"])
        await waitUntilIdle(store)
        store.enqueue(titles: ["The Godfather"])
        await waitUntilIdle(store)

        XCTAssertEqual(calls, 1)
        XCTAssertNil(store.overview(forTitle: "The Godfather"))
    }

    func testBatchesAreDeduplicatedAndCappedAtOneHundred() async throws {
        var batchSizes: [Int] = []
        let store = MetadataStore(lookup: { items in
            batchSizes.append(items.count)
            return items.map { _ in self.makeResult(state: "unresolved", overview: nil) }
        })

        let titles = (0..<150).map { "Unique Movie \($0)" }
        store.enqueue(titles: titles + titles)
        await waitUntilIdle(store)

        XCTAssertEqual(batchSizes, [100, 50])
    }

    func testCommercialTitlesAreNotQueued() async throws {
        var requests: [[MetadataLookup]] = []
        let store = MetadataStore(lookup: { items in
            requests.append(items)
            return items.map { _ in self.makeResult(state: "unresolved", overview: nil) }
        })

        store.enqueue(titles: ["COMMERCIAL BREAK | Station Bumper", "The Godfather", "The Godfather"])
        await waitUntilIdle(store)

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.map(\.name), ["The Godfather"])
    }

    // MARK: - Helpers

    private func makeResult(
        state: String,
        overview: String?,
        confidence: Double? = 1,
        refusal: String? = nil,
        status: Int = 200,
        lookupId: String? = nil
    ) -> MetadataLookupResult {
        MetadataLookupResult(
            lookupId: lookupId,
            state: state,
            partial: false,
            cached: false,
            confidence: confidence,
            refusal: refusal,
            media: overview.map {
                MetadataMedia(
                    kind: "episode",
                    title: "Test",
                    year: 2000,
                    provider: "tmdb",
                    overview: $0
                )
            },
            status: status
        )
    }

    private func waitUntilIdle(_ store: MetadataStore, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !store.isWorking { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Metadata queue did not finish in time")
    }
}
