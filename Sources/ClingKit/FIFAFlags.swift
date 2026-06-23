/**
 FIFA 3-letter country code → flag emoji.

 A match pin travels its teams as FIFA codes (`ARG`, `GER`) because crest images
 can't ride a 4KB Live Activity push (see `ActivityPushContract`); the renderer
 turns the code into a flag here, client-side. FIFA codes are NOT ISO alpha-3
 (`GER` not `DEU`, `NED` not `NLD`), so this maps straight to the emoji rather
 than deriving it — fewer surprises. Unmapped codes fall back to a soccer ball.

 Covers the 2026 World Cup field plus the usual qualifiers; add a row when a new
 nation shows up — it's a lookup, not an exhaustive switch.
 */
import Foundation

enum FIFAFlags {
    static let emoji: [String: String] = [
        // CONMEBOL
        "ARG": "🇦🇷", "BRA": "🇧🇷", "URU": "🇺🇾", "COL": "🇨🇴", "ECU": "🇪🇨",
        "PER": "🇵🇪", "CHI": "🇨🇱", "PAR": "🇵🇾", "BOL": "🇧🇴", "VEN": "🇻🇪",
        // UEFA
        "FRA": "🇫🇷", "GER": "🇩🇪", "ESP": "🇪🇸", "ENG": "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "POR": "🇵🇹",
        "NED": "🇳🇱", "ITA": "🇮🇹", "BEL": "🇧🇪", "CRO": "🇭🇷", "SUI": "🇨🇭",
        "DEN": "🇩🇰", "POL": "🇵🇱", "SRB": "🇷🇸", "AUT": "🇦🇹", "SWE": "🇸🇪",
        "UKR": "🇺🇦", "WAL": "🏴󠁧󠁢󠁷󠁬󠁳󠁿", "SCO": "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "TUR": "🇹🇷", "NOR": "🇳🇴",
        "CZE": "🇨🇿", "HUN": "🇭🇺", "GRE": "🇬🇷", "ROU": "🇷🇴", "SVN": "🇸🇮",
        "SVK": "🇸🇰", "IRL": "🇮🇪", "ISL": "🇮🇸", "FIN": "🇫🇮", "ALB": "🇦🇱",
        // CONCACAF
        "USA": "🇺🇸", "MEX": "🇲🇽", "CAN": "🇨🇦", "CRC": "🇨🇷", "PAN": "🇵🇦",
        "JAM": "🇯🇲", "HON": "🇭🇳", "SLV": "🇸🇻",
        // CAF
        "MAR": "🇲🇦", "SEN": "🇸🇳", "NGA": "🇳🇬", "EGY": "🇪🇬", "CMR": "🇨🇲",
        "GHA": "🇬🇭", "ALG": "🇩🇿", "TUN": "🇹🇳", "CIV": "🇨🇮", "RSA": "🇿🇦",
        "MLI": "🇲🇱", "CPV": "🇨🇻",
        // AFC
        "JPN": "🇯🇵", "KOR": "🇰🇷", "AUS": "🇦🇺", "IRN": "🇮🇷", "KSA": "🇸🇦",
        "QAT": "🇶🇦", "IRQ": "🇮🇶", "UAE": "🇦🇪", "UZB": "🇺🇿", "JOR": "🇯🇴",
        // OFC
        "NZL": "🇳🇿",
    ]
}
