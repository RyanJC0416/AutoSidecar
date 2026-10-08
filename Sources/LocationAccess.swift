import CoreLocation
import Foundation

final class LocationAccess: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onChange: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onChange?()
    }
}
