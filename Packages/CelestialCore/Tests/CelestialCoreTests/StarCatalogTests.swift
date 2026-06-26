import Testing
import Foundation
@testable import CelestialCore

@Suite("Star catalog (HYG)")
struct StarCatalogTests {
    // A faithful slice of real HYG v4.1 rows (Sol, Sirius, Canopus, Vega, Polaris),
    // plus one synthetic row using the 100000-parsec "unknown distance" sentinel.
    static let fixture = #"""
    "id","hip","hd","hr","gl","bf","proper","ra","dec","dist","pmra","pmdec","rv","mag","absmag","spect","ci","x","y","z","vx","vy","vz","rarad","decrad","pmrarad","pmdecrad","bayer","flam","con","comp","comp_primary","base","lum","var","var_min","var_max"
    0,,,,"","",Sol,0.0,0.0,0.0,0.0,0.0,0.0,-26.7,4.85,G2V,0.656,0.000005,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,"","","",1,0,"",1.0,"",,
    32263,32349,48915,2491,Gl 244A,"9Alp CMa",Sirius,6.752481,-16.716116,2.6371,-546.01,-1223.08,-9.4,-1.44,1.454,A0m...,0.009,-0.494323,2.476731,-0.758485,0.00000953,-0.00001207,-0.00001221,1.7677953696021995,-0.291751258517685,-0.0000026471311772,-0.000005929659164,Alp,"9",CMa,1,32263,Gl 244,22.824433121735034,"",-1.333,-1.523
    30365,30438,45348,2326,"",Alp Car,Canopus,6.399195,-52.69566,94.7867,19.99,23.67,21.0,-0.62,-5.504,F0Ib,0.164,-5.992679,57.132034,-75.396105,-0.0000114,0.00002059,-0.00001049,1.6753053519997292,-0.9197127748902675,0.0000000969142547,0.000000114755398,Alp,"",Car,1,30365,"",13854.791675667215,"",-0.547,-0.667
    90979,91262,172167,7001,Gl 721,"3Alp Lyr",Vega,18.61564,38.783692,7.6787,201.02,287.46,-12.1,0.03,0.604,A0Vvar,-0.001,0.960565,-5.908009,4.809731,0.00000476,0.00001734,0.00000059,4.873563095509031,0.6769031163973025,0.0000009745724607,0.000001393645406,Alp,"3",Lyr,1,90979,"",49.93441887213498,"",,
    11734,11767,8890,424,"","1Alp UMi",Polaris,2.52975,89.264109,132.626,44.22,-11.74,-17.0,1.97,-3.643,F7:Ib-IIv SB,0.636,1.3431,1.047629,132.614909,-0.00001171,0.00002692,-0.00001748,0.6622870748653336,1.5579526129751475,0.0000002143846095,-0.000000056917126,Alp,"1",UMi,1,11734,"",2495.743794831569,Alp,1.993,1.953
    999001,,,,"","",UnknownDistStar,12.0,45.0,100000.0,0.0,0.0,0.0,11.5,0.0,M0V,1.4,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,"","","",1,999001,"",0.0,"",,
    """#

    func makeCatalog() throws -> StarCatalog {
        try StarCatalog.hyg(csv: Self.fixture)
    }

    @Test("parses every data row")
    func rowCount() throws {
        #expect(try makeCatalog().count == 6)
    }

    @Test("maps named fields and converts units")
    func siriusFields() throws {
        let sirius = try #require(try makeCatalog().star(named: "sirius"))  // case-insensitive
        #expect(sirius.hipparcos == 32349)
        #expect(sirius.harvardRevised == 2491)
        #expect(sirius.spectralType == "A0m...")
        #expect(sirius.bayerFlamsteed == "9Alp CMa")     // quoted field survives intact
        #expect(sirius.constellation == "CMa")
        // RA stored in hours → 6.752481 h == 101.287° ; Dec in degrees.
        #expect(abs(sirius.equatorial.rightAscension.hours - 6.752481) < 1e-6)
        #expect(abs(sirius.equatorial.rightAscension.degrees - 101.287215) < 1e-4)
        #expect(abs(sirius.equatorial.declination.degrees - (-16.716116)) < 1e-6)
        #expect(abs((sirius.distanceParsecs ?? -1) - 2.6371) < 1e-6)
        #expect(sirius.position != nil)
    }

    @Test("Sol keeps a real zero distance (not treated as unknown)")
    func solDistance() throws {
        let sol = try #require(try makeCatalog().star(named: "Sol"))
        #expect(sol.distanceParsecs == 0)
        #expect(sol.position != nil)
    }

    @Test("the 100000-pc sentinel becomes an unknown distance")
    func unknownDistanceSentinel() throws {
        let star = try #require(try makeCatalog().star(named: "UnknownDistStar"))
        #expect(star.distanceParsecs == nil)
        #expect(star.position == nil)        // no 3D placement without a distance
    }

    @Test("lookup by Hipparcos number")
    func hipparcosLookup() throws {
        let polaris = try #require(try makeCatalog().star(hipparcos: 11767))
        #expect(polaris.properName == "Polaris")
    }

    @Test("brightest() orders by apparent magnitude")
    func brightestOrdering() throws {
        let names = try makeCatalog().brightest(3).map(\.properName)
        #expect(names == ["Sol", "Sirius", "Canopus"])
    }

    @Test("magnitude filter")
    func brighterThan() throws {
        let catalog = try makeCatalog()
        let bright = catalog.stars(brighterThan: 0.1).map(\.properName)
        #expect(bright.contains("Vega"))         // 0.03
        #expect(!bright.contains("Polaris"))     // 1.97
    }

    @Test("only known-distance stars are 3D-placeable")
    func knownDistanceSubset() throws {
        let catalog = try makeCatalog()
        #expect(catalog.starsWithKnownDistance.count == 5)   // all but the sentinel row
    }

    @Test("missing required column throws")
    func missingColumn() {
        let bad = "id,ra,dec\n0,0,0"   // no "mag"
        #expect(throws: HYGCatalog.ParseError.missingColumn("mag")) {
            _ = try HYGCatalog.parse(csv: bad)
        }
    }
}
