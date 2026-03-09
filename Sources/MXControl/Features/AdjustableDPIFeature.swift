import Foundation

/// HID++ 2.0 AdjustableDPI (0x2201) — DPI settings for mouse sensors.
///
/// Functions:
///   0: getSensorCount()          -> number of sensors
///   1: getSensorDPIList(sensor)  -> supported DPI values/range
///   2: getSensorDPI(sensor)      -> current DPI + default DPI
///   3: setSensorDPI(sensor, dpi) -> set DPI value
enum AdjustableDPIFeature {

    static let featureId: UInt16 = 0x2201

    // MARK: - DPI List

    /// DPI range or list of supported DPI values.
    enum DPIList: Sendable {
        /// Continuous range: min to max, with step size.
        case range(min: Int, max: Int, step: Int)
        /// Discrete list of supported DPI values.
        case list([Int])
    }

    // MARK: - Sensor DPI Info

    struct SensorDPIInfo: Sendable {
        /// Current DPI value.
        let currentDPI: Int
        /// Default DPI value.
        let defaultDPI: Int
    }

    // MARK: - Function 0: GetSensorCount

    /// Get the number of DPI sensors.
    /// Most mice have 1 sensor. Gaming mice may have independent X/Y sensors.
    static func getSensorCount(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8
    ) async throws -> Int {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x00,
            softwareId: 0x01
        )

        return Int(response.params[0])
    }

    // MARK: - Function 1: GetSensorDPIList

    /// Get the supported DPI values for a sensor.
    ///
    /// The response encodes either a range (if bit 13 of a 16-bit value is set)
    /// or a list of discrete DPI values (terminated by 0x0000).
    ///
    /// Range format: [min_hi, min_lo, step_hi, step_lo, max_hi, max_lo]
    ///   where step has bit 13 (0x2000) set to indicate "this is a step value".
    ///
    /// List format: [dpi1_hi, dpi1_lo, dpi2_hi, dpi2_lo, ..., 0x00, 0x00]
    static func getSensorDPIList(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        sensorIndex: UInt8 = 0
    ) async throws -> DPIList {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x01,
            softwareId: 0x01,
            params: [sensorIndex]
        )

        let params = response.params

        // Parse 16-bit values from the param array
        var values: [UInt16] = []
        var i = 0
        while i + 1 < params.count {
            let val = (UInt16(params[i]) << 8) | UInt16(params[i + 1])
            if val == 0 { break }
            values.append(val)
            i += 2
        }

        guard values.count >= 1 else {
            return .list([])
        }

        // Check if the second value has the range indicator bit (0xE000 mask)
        // If bit 13 is set in the step value, it's a range: [min, step|0x2000, max]
        if values.count >= 3 {
            let possibleStep = values[1]
            if (possibleStep & 0xE000) != 0 {
                let min = Int(values[0])
                let step = Int(possibleStep & 0x1FFF)  // Clear indicator bits
                let max = Int(values[2])
                return .range(min: min, max: max, step: step > 0 ? step : 1)
            }
        }

        // Otherwise it's a list of discrete DPI values
        return .list(values.map { Int($0) })
    }

    // MARK: - Function 2: GetSensorDPI

    /// Get the current and default DPI for a sensor.
    ///
    /// Response format:
    ///   param[0-1]: sensorIndex + current DPI (big-endian)
    ///   param[2-3]: default DPI (big-endian)
    static func getSensorDPI(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        sensorIndex: UInt8 = 0
    ) async throws -> SensorDPIInfo {
        let response = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x02,
            softwareId: 0x01,
            params: [sensorIndex]
        )

        let params = response.params
        // param[0] = sensorIndex echo
        // param[1-2] = current DPI (big-endian)
        let currentDPI = (Int(params[1]) << 8) | Int(params[2])
        // param[3-4] = default DPI (big-endian)
        let defaultDPI = params.count >= 5
            ? (Int(params[3]) << 8) | Int(params[4])
            : currentDPI

        return SensorDPIInfo(
            currentDPI: currentDPI,
            defaultDPI: defaultDPI
        )
    }

    // MARK: - Function 3: SetSensorDPI

    /// Set the DPI for a sensor.
    ///
    /// - Parameters:
    ///   - dpi: Target DPI value (will be clamped to device range).
    ///   - sensorIndex: Sensor to configure (default 0).
    static func setSensorDPI(
        transport: HIDTransport,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        sensorIndex: UInt8 = 0,
        dpi: Int
    ) async throws {
        let _ = try await transport.send(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionId: 0x03,
            softwareId: 0x01,
            params: [
                sensorIndex,
                UInt8((dpi >> 8) & 0xFF),
                UInt8(dpi & 0xFF),
            ]
        )
    }
}
