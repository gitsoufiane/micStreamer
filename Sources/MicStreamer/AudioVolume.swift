enum AudioVolume {
    static func clamped(_ volume: Double) -> Double {
        min(max(volume, 0.0), 2.0)
    }

    static func clamped(_ volume: Float) -> Float {
        min(max(volume, 0), 2)
    }

    static func title(_ volume: Double) -> String {
        "\(Int((volume * 100).rounded()))%"
    }

    static func scale(_ sample: Int16, by volume: Float) -> Int16 {
        let scaled = Int(Float(sample) * volume)
        return Int16(min(max(scaled, Int(Int16.min)), Int(Int16.max)))
    }

    static func scale(_ sample: Int32, by volume: Float) -> Int32 {
        let scaled = Int64(Double(sample) * Double(volume))
        return Int32(min(max(scaled, Int64(Int32.min)), Int64(Int32.max)))
    }
}
