public enum TokenCountFormatter {
    public static func short(_ tokens: UInt64) -> String {
        if tokens >= 1_000_000_000 {
            return "\(compact(tokens, unit: 1_000_000_000))B tokens"
        }
        if tokens >= 1_000_000 {
            return "\(compact(tokens, unit: 1_000_000))M tokens"
        }
        return "\(grouped(tokens)) tokens"
    }

    private static func compact(_ value: UInt64, unit: UInt64) -> String {
        let tenths = value / (unit / 10)
        let whole = tenths / 10
        let decimal = tenths % 10
        return decimal == 0 ? "\(whole)" : "\(whole).\(decimal)"
    }

    private static func grouped(_ value: UInt64) -> String {
        let reversedDigits = String(value).reversed()
        var groupedDigits = ""

        for (index, digit) in reversedDigits.enumerated() {
            if index > 0, index.isMultiple(of: 3) {
                groupedDigits.append(",")
            }
            groupedDigits.append(digit)
        }

        return String(groupedDigits.reversed())
    }
}
