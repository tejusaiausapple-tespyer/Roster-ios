import Foundation
import MapKit
import Combine

/// Wraps MKLocalSearchCompleter to provide native address autocomplete,
/// replacing the web app's Google Places autocomplete in profile completion.
final class AddressSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var suggestions: [String] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        guard query.count >= 3 else {
            suggestions = []
            return
        }
        completer.queryFragment = query
    }

    func clear() {
        suggestions = []
        completer.queryFragment = ""
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.prefix(4).map { result in
            result.subtitle.isEmpty ? result.title : "\(result.title), \(result.subtitle)"
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
