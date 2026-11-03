import XCTest

/// Photographs the debug-only Element Gallery (launch argument -elementGallery), one screenful per page,
/// for Saidie's Liquid Glass markup (Nov 3 2026). Pages are gallery-01, gallery-02, … (+ "-dark" in dark runs).
final class ElementGalleryUITests: DisciplineUITestCase {
    func testElementGalleryPages() {
        launch(["-elementGallery"])
        let next = el("gallery.next")
        XCTAssertTrue(next.waitForExistence(timeout: 30), "the Element Gallery did not open")
        sleep(3)
        for page in 1...40 {
            snap(String(format: "gallery-%02d", page))
            if el("gallery.done").exists {
                note("gallery-pages", "\(page) pages")
                return
            }
            next.tap()
            sleep(2)
        }
        XCTFail("the gallery did not reach its last page in 40 pages")
    }
}
