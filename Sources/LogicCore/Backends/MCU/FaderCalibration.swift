import Foundation

/// MCU fader value (14-bit) ↔ Logic dB.
///
/// Points are Logic Control.bundle's own conversion table
/// (`CSFaderDBConversionTable`, Logic 12.3.1 build 6682: 35 entries of
/// value + 16.16 fixed-point dB, first entry 0 ↔ -144 dB, shown as -oo), found with
/// Ghidra. Logic interpolates linearly between them: that reproduced all 58
/// LCD readings of the EXP-MCU-009 sweep to 0.1 dB.
/// Writes stay closed-loop on the LCD readback regardless.
public enum FaderCalibration {
    public static let points: [(value: Int, db: Double)] = [
        (0, -144), (192, -70), (457, -60), (695, -57.5), (994, -55), (1234, -52.5), (1446, -50),
        (1753, -47.5), (2027, -45), (2285, -42.5), (2564, -40), (2797, -37.5), (3058, -35),
        (3567, -32.5), (3990, -30), (4416, -26.6667), (4912, -23.3333), (5293, -20), (5771, -18),
        (6256, -16), (6701, -14), (7177, -12), (7602, -10), (8084, -9.1667), (8553, -8.3333),
        (9017, -7.5), (9485, -6.6667), (9970, -5.8333), (10450, -5), (12441, 0), (14459, 5),
        (14939, 6.25), (15440, 7.5), (15904, 8.75), (16380, 10),
    ]
    /// Channel strips stop at +6 dB (EXP-MCU-009), although the table goes to +10.
    public static let maxValue = 14843
    public static let maxDB = 6.0

    /// Fader value for a dB target (first guess for the closed loop).
    public static func value(forDB db: Double) -> Int {
        if db.isInfinite && db < 0 { return 0 }
        if db >= maxDB { return maxValue }
        if db <= points[0].db { return 0 }
        for (a, b) in zip(points, points.dropFirst()) where db <= b.db {
            let t = (db - a.db) / (b.db - a.db)
            return Int((Double(a.value) + t * Double(b.value - a.value)).rounded())
        }
        return maxValue
    }

    /// dB for a fader value, as Logic computes it (matches its LCD to 0.1 dB).
    public static func db(forValue value: Int) -> Double {
        if value <= 0 { return -.infinity }
        for (a, b) in zip(points, points.dropFirst()) where value <= b.value {
            let t = Double(value - a.value) / Double(b.value - a.value)
            return a.db + t * (b.db - a.db)
        }
        return maxDB
    }
}
