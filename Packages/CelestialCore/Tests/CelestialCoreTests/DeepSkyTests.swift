import Testing
import Foundation
@testable import CelestialCore

@Suite("Deep-sky catalog (Messier + famous NGC)")
struct DeepSkyTests {

    @Test("the full Messier list is present: 110 objects, M1…M110, no gaps")
    func messierCompleteness() {
        let messier = DeepSky.messier
        #expect(messier.count == 110)

        let numbers = Set(messier.compactMap(\.messier))
        #expect(numbers == Set(1...110))   // every number 1…110 exactly once

        // Ids follow the "M<n>" convention.
        for object in messier {
            #expect(object.id == "M\(object.messier!)")
        }
    }

    @Test("catalog combines Messier + NGC extras with no duplicate ids")
    func allCombined() {
        let all = DeepSky.all
        #expect(all.count == DeepSky.messier.count + DeepSky.ngcExtras.count)
        #expect(all.count >= 110)

        let ids = all.map(\.id)
        #expect(Set(ids).count == ids.count)   // ids are unique
    }

    private func object(_ id: String) -> DeepSkyObject {
        DeepSky.all.first { $0.id == id }!
    }

    @Test("M31 is the Andromeda Galaxy: galaxy in And at RA≈10.68° Dec≈+41.27° mag≈3.4")
    func andromeda() {
        let m31 = object("M31")
        #expect(m31.kind == .galaxy)
        #expect(m31.constellation == "And")
        #expect(m31.name == "Andromeda Galaxy")
        #expect(abs(m31.equatorial.rightAscension.degrees - 10.68) <= 0.2)
        #expect(abs(m31.equatorial.declination.degrees - 41.27) <= 0.2)
        #expect(abs((m31.magnitude ?? 0) - 3.4) <= 0.3)
    }

    @Test("M42 is an emission nebula in Orion")
    func orionNebula() {
        let m42 = object("M42")
        #expect(m42.kind == .emissionNebula)
        #expect(m42.constellation == "Ori")
        // Orion's Sword: RA ≈ 83.8°, Dec ≈ -5.4°
        #expect(abs(m42.equatorial.rightAscension.degrees - 83.82) <= 0.2)
        #expect(abs(m42.equatorial.declination.degrees - (-5.39)) <= 0.2)
    }

    @Test("M13 is a globular cluster in Hercules")
    func herculesCluster() {
        let m13 = object("M13")
        #expect(m13.kind == .globularCluster)
        #expect(m13.constellation == "Her")
    }

    @Test("M45 (Pleiades) is in Taurus")
    func pleiades() {
        let m45 = object("M45")
        #expect(m45.constellation == "Tau")
        #expect(m45.kind == .openCluster)
    }

    @Test("the famous NGC extras are present")
    func ngcExtras() {
        let ids = Set(DeepSky.all.map(\.id))
        for id in ["NGC 869", "NGC 884", "NGC 7000", "NGC 253",
                   "NGC 5128", "NGC 6960", "NGC 6992", "NGC 7293",
                   "NGC 5139", "NGC 104"] {
            #expect(ids.contains(id), "missing \(id)")
        }
        // None of the extras carry a Messier number.
        for object in DeepSky.ngcExtras {
            #expect(object.messier == nil)
            #expect(object.ngc != nil)
        }
    }

    @Test("query helpers filter correctly")
    func queries() {
        // inConstellation is case-insensitive and matches both Messier and NGC.
        let virgo = DeepSky.inConstellation("vir")
        #expect(virgo.count > 5)
        #expect(virgo.allSatisfy { $0.constellation == "Vir" })

        // ofKind returns only the requested kind.
        let galaxies = DeepSky.ofKind(.galaxy)
        #expect(galaxies.allSatisfy { $0.kind == .galaxy })
        #expect(galaxies.contains { $0.id == "M31" })

        // brightest is sorted ascending by magnitude (Pleiades, mag 1.6, is brightest).
        let brightest = DeepSky.brightest
        #expect(brightest.first?.id == "M45")
        let mags = brightest.compactMap(\.magnitude)
        #expect(mags == mags.sorted())
    }
}
