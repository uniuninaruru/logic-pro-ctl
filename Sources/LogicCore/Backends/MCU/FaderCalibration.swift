import Foundation

/// MCU fader value (14-bit) ↔ Logic dB, measured on Logic 12.3.1 (6682)
/// by EXP-MCU-009 (Research/protocol/mcu-fader-calibration.tsv): pairs of
/// the value Logic echoed back and the dB shown on its LCD.
///
/// Used only for the first guess and for coarse reads; writes are closed-loop
/// on the LCD readback, so calibration error does not reach the result.
public enum FaderCalibration {
    public static let points: [(value: Int, db: Double)] = [
        (255, -67.6), (504, -59.5), (766, -56.9), (1022, -54.7), (1276, -52.0), (1531, -49.3),
        (1785, -47.2), (2047, -44.8), (2296, -42.4), (2552, -40.1), (2807, -37.4), (3058, -35.0),
        (3322, -33.7), (3583, -32.4), (3837, -30.9), (4092, -29.2), (4347, -27.2), (4604, -25.4),
        (4857, -23.7), (5110, -21.6), (5364, -19.7), (5628, -18.6), (5869, -17.6), (6135, -16.5),
        (6390, -15.4), (6635, -14.3), (6892, -13.2), (7154, -12.1), (7411, -10.9), (7660, -9.9),
        (7892, -9.5), (8178, -9.0), (8403, -8.6), (8683, -8.1), (8906, -7.7), (9186, -7.2),
        (9467, -6.7), (9699, -6.3), (9932, -5.9), (10220, -5.4), (10490, -4.9), (10729, -4.3),
        (11009, -3.6), (11248, -3.0), (11487, -2.4), (11766, -1.7), (12004, -1.1), (12283, -0.4),
        (12443, 0.0), (12523, 0.2), (12765, 0.8), (13048, 1.5), (13290, 2.1), (13532, 2.7),
        (13815, 3.4), (14057, 4.0), (14299, 4.6), (14576, 5.3), (14845, 6.0),
    ]
    public static let maxValue = 14845
    public static let maxDB = 6.0

    /// Fader value for a dB target (first guess for the closed loop).
    public static func value(forDB db: Double) -> Int {
        if db.isInfinite && db < 0 { return 0 }
        if db >= maxDB { return maxValue }
        let first = points[0]
        if db <= first.db {
            // Below the measured range: shrink linearly towards 0.
            return max(1, Int((Double(first.value) * (db + 96) / (first.db + 96)).rounded()))
        }
        for (a, b) in zip(points, points.dropFirst()) where db <= b.db {
            let t = (db - a.db) / (b.db - a.db)
            return Int((Double(a.value) + t * Double(b.value - a.value)).rounded())
        }
        return maxValue
    }

    /// dB for a fader value (coarse read; ±0.3 dB between points).
    public static func db(forValue value: Int) -> Double {
        if value <= 0 { return -.infinity }
        let first = points[0]
        if value <= first.value { return first.db }
        for (a, b) in zip(points, points.dropFirst()) where value <= b.value {
            let t = Double(value - a.value) / Double(b.value - a.value)
            return a.db + t * (b.db - a.db)
        }
        return maxDB
    }
}
