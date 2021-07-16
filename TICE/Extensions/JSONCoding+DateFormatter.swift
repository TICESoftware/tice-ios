//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

extension ISO8601DateFormatter {
    static var formatterWithFractionalSeconds: ISO8601DateFormatter {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions.insert(.withFractionalSeconds)
        return dateFormatter
    }
}

extension JSONEncoder {
    static var encoderWithFractionalSeconds: JSONEncoder {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .custom({ date, encoder in
            let dateString = ISO8601DateFormatter.formatterWithFractionalSeconds.string(from: date)
            var container = encoder.singleValueContainer()
            try container.encode(dateString)
        })
        return jsonEncoder
    }
}

extension JSONDecoder {
    static var decoderWithFractionalSeconds: JSONDecoder {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .custom({ decoder -> Date in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            return ISO8601DateFormatter.formatterWithFractionalSeconds.date(from: dateString)!
        })
        return jsonDecoder
    }
}
