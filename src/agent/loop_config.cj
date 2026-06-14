package cangjiecoder.agent

import std.convert.*
import std.env.*

const DEFAULT_MAX_ITERATIONS = 256

func defaultMaxIterations(): Int64 {
    match (getVariable("CANGJIECODER_MAX_ITERATIONS")) {
        case Some(v) =>
            let parsed = Int64.tryParse(v.trimAscii()) ?? DEFAULT_MAX_ITERATIONS
            return if (parsed > 0) {
                parsed
            } else {
                DEFAULT_MAX_ITERATIONS
            }
        case None => return DEFAULT_MAX_ITERATIONS
    }
}
