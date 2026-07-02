import Testing
import CelestialCore
@testable import Astrology

@Suite struct TransitTests {
    @Test func saturnReturnIsDetected() {
        // Transiting Saturn at the same longitude as natal Saturn → conjunction.
        let natal = [BodyPosition(body: .saturn, longitude: .degrees(100))]
        let transiting = [BodyPosition(body: .saturn, longitude: .degrees(101), speed: 0.03)]
        let hits = Transits.hits(transiting: transiting, natal: natal)
        #expect(hits.contains { $0.transiting == .saturn && $0.natal == .saturn && $0.kind == .conjunction })
    }

    @Test func hitsSortedByOrb() {
        let natal = [
            BodyPosition(body: .sun, longitude: .degrees(0)),
            BodyPosition(body: .moon, longitude: .degrees(90)),
        ]
        let transiting = [
            BodyPosition(body: .mars, longitude: .degrees(3), speed: 0.5),   // 3° from Sun (conj)
            BodyPosition(body: .mars, longitude: .degrees(3), speed: 0.5),
        ]
        let hits = Transits.hits(transiting: transiting, natal: natal)
        #expect(!hits.isEmpty)
        // Tightest first.
        #expect(hits == hits.sorted { $0.orb < $1.orb })
    }

    @Test func applyingDetected() {
        let natal = [BodyPosition(body: .sun, longitude: .degrees(10))]
        // Mars at 6°, moving forward toward 10° → applying conjunction.
        let transiting = [BodyPosition(body: .mars, longitude: .degrees(6), speed: 0.5)]
        let hit = Transits.hits(transiting: transiting, natal: natal).first { $0.kind == .conjunction }
        #expect(hit?.isApplying == true)
    }
}

@Suite struct InterpretationTests {
    @Test func everyCombinationProducesText() {
        // No nil-unwrap traps: all tables must be complete across the enums.
        for s in ZodiacSign.allCases { #expect(!Interpretation.sign(s).isEmpty) }
        for b in AstroBody.allCases {
            for s in ZodiacSign.allCases { #expect(!Interpretation.planetInSign(b, s).isEmpty) }
            for h in 1...12 { #expect(!Interpretation.planetInHouse(b, h).isEmpty) }
        }
        for k in AspectKind.allCases {
            #expect(!Interpretation.aspect(k, .sun, .moon).isEmpty)
        }
    }

    @Test func articleAgreesWithVowel() {
        #expect(Interpretation.planetInSign(.sun, .scorpio).contains("in an intense"))   // vowel
        #expect(Interpretation.planetInSign(.sun, .taurus).contains("in a steady"))      // consonant
        // No "in a <vowel>" slips through for any planet/sign.
        for b in AstroBody.allCases {
            for s in ZodiacSign.allCases {
                let t = Interpretation.planetInSign(b, s)
                #expect(!t.contains("a intense") && !t.contains("a original")
                        && !t.contains("a adventurous") && !t.contains("a imaginative"))
            }
        }
    }

    @Test func readsNaturally() {
        #expect(Interpretation.planetInSign(.sun, .leo)
            .contains("Sun is in Leo"))
        #expect(Interpretation.planetInHouse(.moon, 4).contains("4th house"))
        #expect(Interpretation.aspect(.trine, .venus, .mars).contains("Venus trine Mars"))
    }
}
