import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Transferable wrapper for a local race-report JSON export.
struct ReplayRaceReportTransferItem: Transferable {
    let data: Data
    let suggestedName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { item in
            item.data
        }
        .suggestedFileName { item in
            item.suggestedName
        }
    }
}

/// Transferable wrapper for a local race-card PNG export.
struct ReplayRaceCardTransferItem: Transferable {
    let data: Data
    let suggestedName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.data
        }
        .suggestedFileName { item in
            item.suggestedName
        }
    }
}
