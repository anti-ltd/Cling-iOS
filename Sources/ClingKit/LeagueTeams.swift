/**
 Static team rosters for the unified Game composer's dropdowns.

 The quick-add form no longer asks the user to hand-type a team code — it shows
 a league dropdown and two team dropdowns sourced from here. Each `LeagueTeam`
 carries the short code the payload travels as (`LAL`, `ARG`) plus a readable
 name for the menu row.

 World Cup codes are the FIFA 3-letter codes, so they must stay in lockstep with
 `FIFAFlags.emoji` (the renderer turns the code into a flag). Add a nation to
 both when a new one shows up. US-league codes are ESPN's scoreboard
 abbreviations — they only need to read right in the menu, since a manually
 created card is static until it's connected to a live fixture from the browser.
 */
import Foundation

public struct LeagueTeam: Hashable, Sendable, Identifiable {
    /// The short code the payload stores (`LAL`, `ARG`).
    public let abbr: String
    /// The menu label ("Los Angeles Lakers", "Argentina").
    public let name: String

    public var id: String { abbr }

    public init(abbr: String, name: String) {
        self.abbr = abbr
        self.name = name
    }
}

public enum LeagueTeams {
    /// The leagues the unified Game composer offers, World Cup first. UFC is
    /// excluded — it has its own Fight pin (fighters, not a team roster).
    public static let creatableLeagues: [SportLeague] = [.worldCup, .nba, .nfl, .nhl, .mlb]

    /// The roster for a league, sorted for the dropdown. Empty for leagues with
    /// no static roster (e.g. UFC).
    public static func teams(for league: SportLeague) -> [LeagueTeam] {
        switch league {
        case .worldCup: worldCup
        case .nba:      nba
        case .nfl:      nfl
        case .nhl:      nhl
        case .mlb:      mlb
        case .ufc:      []
        }
    }

    /// Look a team up by code within a league — for resolving a name from a
    /// stored abbreviation.
    public static func team(abbr: String, in league: SportLeague) -> LeagueTeam? {
        let key = abbr.uppercased()
        return teams(for: league).first { $0.abbr == key }
    }

    // MARK: Rosters

    /// FIFA nations — codes match `FIFAFlags.emoji` so the flag always resolves.
    static let worldCup: [LeagueTeam] = [
        ("ALB", "Albania"), ("ALG", "Algeria"), ("ARG", "Argentina"),
        ("AUS", "Australia"), ("AUT", "Austria"), ("BEL", "Belgium"),
        ("BOL", "Bolivia"), ("BRA", "Brazil"), ("CMR", "Cameroon"),
        ("CAN", "Canada"), ("CPV", "Cape Verde"), ("CHI", "Chile"),
        ("COL", "Colombia"),
        ("CRC", "Costa Rica"), ("CIV", "Côte d'Ivoire"), ("CRO", "Croatia"),
        ("CZE", "Czechia"), ("DEN", "Denmark"), ("ECU", "Ecuador"),
        ("EGY", "Egypt"), ("SLV", "El Salvador"), ("ENG", "England"),
        ("FIN", "Finland"), ("FRA", "France"), ("GER", "Germany"),
        ("GHA", "Ghana"), ("GRE", "Greece"), ("HON", "Honduras"),
        ("HUN", "Hungary"), ("ISL", "Iceland"), ("IRN", "Iran"),
        ("IRQ", "Iraq"), ("IRL", "Ireland"), ("ITA", "Italy"),
        ("JAM", "Jamaica"), ("JPN", "Japan"), ("JOR", "Jordan"),
        ("KOR", "South Korea"), ("MLI", "Mali"), ("MEX", "Mexico"),
        ("MAR", "Morocco"), ("NED", "Netherlands"), ("NZL", "New Zealand"),
        ("NGA", "Nigeria"), ("NOR", "Norway"), ("PAN", "Panama"),
        ("PAR", "Paraguay"), ("PER", "Peru"), ("POL", "Poland"),
        ("POR", "Portugal"), ("QAT", "Qatar"), ("ROU", "Romania"),
        ("KSA", "Saudi Arabia"), ("SCO", "Scotland"), ("SEN", "Senegal"),
        ("SRB", "Serbia"), ("SVK", "Slovakia"), ("SVN", "Slovenia"),
        ("RSA", "South Africa"), ("ESP", "Spain"), ("SWE", "Sweden"),
        ("SUI", "Switzerland"), ("TUN", "Tunisia"), ("TUR", "Türkiye"),
        ("UKR", "Ukraine"), ("UAE", "United Arab Emirates"),
        ("USA", "United States"), ("URU", "Uruguay"), ("UZB", "Uzbekistan"),
        ("VEN", "Venezuela"), ("WAL", "Wales"),
    ].map { LeagueTeam(abbr: $0.0, name: $0.1) }

    static let nba: [LeagueTeam] = [
        ("ATL", "Atlanta Hawks"), ("BOS", "Boston Celtics"),
        ("BKN", "Brooklyn Nets"), ("CHA", "Charlotte Hornets"),
        ("CHI", "Chicago Bulls"), ("CLE", "Cleveland Cavaliers"),
        ("DAL", "Dallas Mavericks"), ("DEN", "Denver Nuggets"),
        ("DET", "Detroit Pistons"), ("GS", "Golden State Warriors"),
        ("HOU", "Houston Rockets"), ("IND", "Indiana Pacers"),
        ("LAC", "LA Clippers"), ("LAL", "Los Angeles Lakers"),
        ("MEM", "Memphis Grizzlies"), ("MIA", "Miami Heat"),
        ("MIL", "Milwaukee Bucks"), ("MIN", "Minnesota Timberwolves"),
        ("NO", "New Orleans Pelicans"), ("NY", "New York Knicks"),
        ("OKC", "Oklahoma City Thunder"), ("ORL", "Orlando Magic"),
        ("PHI", "Philadelphia 76ers"), ("PHX", "Phoenix Suns"),
        ("POR", "Portland Trail Blazers"), ("SAC", "Sacramento Kings"),
        ("SA", "San Antonio Spurs"), ("TOR", "Toronto Raptors"),
        ("UTAH", "Utah Jazz"), ("WSH", "Washington Wizards"),
    ].map { LeagueTeam(abbr: $0.0, name: $0.1) }

    static let nfl: [LeagueTeam] = [
        ("ARI", "Arizona Cardinals"), ("ATL", "Atlanta Falcons"),
        ("BAL", "Baltimore Ravens"), ("BUF", "Buffalo Bills"),
        ("CAR", "Carolina Panthers"), ("CHI", "Chicago Bears"),
        ("CIN", "Cincinnati Bengals"), ("CLE", "Cleveland Browns"),
        ("DAL", "Dallas Cowboys"), ("DEN", "Denver Broncos"),
        ("DET", "Detroit Lions"), ("GB", "Green Bay Packers"),
        ("HOU", "Houston Texans"), ("IND", "Indianapolis Colts"),
        ("JAX", "Jacksonville Jaguars"), ("KC", "Kansas City Chiefs"),
        ("LV", "Las Vegas Raiders"), ("LAC", "Los Angeles Chargers"),
        ("LAR", "Los Angeles Rams"), ("MIA", "Miami Dolphins"),
        ("MIN", "Minnesota Vikings"), ("NE", "New England Patriots"),
        ("NO", "New Orleans Saints"), ("NYG", "New York Giants"),
        ("NYJ", "New York Jets"), ("PHI", "Philadelphia Eagles"),
        ("PIT", "Pittsburgh Steelers"), ("SF", "San Francisco 49ers"),
        ("SEA", "Seattle Seahawks"), ("TB", "Tampa Bay Buccaneers"),
        ("TEN", "Tennessee Titans"), ("WSH", "Washington Commanders"),
    ].map { LeagueTeam(abbr: $0.0, name: $0.1) }

    static let nhl: [LeagueTeam] = [
        ("ANA", "Anaheim Ducks"), ("BOS", "Boston Bruins"),
        ("BUF", "Buffalo Sabres"), ("CGY", "Calgary Flames"),
        ("CAR", "Carolina Hurricanes"), ("CHI", "Chicago Blackhawks"),
        ("COL", "Colorado Avalanche"), ("CBJ", "Columbus Blue Jackets"),
        ("DAL", "Dallas Stars"), ("DET", "Detroit Red Wings"),
        ("EDM", "Edmonton Oilers"), ("FLA", "Florida Panthers"),
        ("LA", "Los Angeles Kings"), ("MIN", "Minnesota Wild"),
        ("MTL", "Montréal Canadiens"), ("NSH", "Nashville Predators"),
        ("NJ", "New Jersey Devils"), ("NYI", "New York Islanders"),
        ("NYR", "New York Rangers"), ("OTT", "Ottawa Senators"),
        ("PHI", "Philadelphia Flyers"), ("PIT", "Pittsburgh Penguins"),
        ("SJ", "San Jose Sharks"), ("SEA", "Seattle Kraken"),
        ("STL", "St. Louis Blues"), ("TB", "Tampa Bay Lightning"),
        ("TOR", "Toronto Maple Leafs"), ("UTAH", "Utah Hockey Club"),
        ("VAN", "Vancouver Canucks"), ("VGK", "Vegas Golden Knights"),
        ("WSH", "Washington Capitals"), ("WPG", "Winnipeg Jets"),
    ].map { LeagueTeam(abbr: $0.0, name: $0.1) }

    static let mlb: [LeagueTeam] = [
        ("ARI", "Arizona Diamondbacks"), ("ATL", "Atlanta Braves"),
        ("BAL", "Baltimore Orioles"), ("BOS", "Boston Red Sox"),
        ("CHC", "Chicago Cubs"), ("CWS", "Chicago White Sox"),
        ("CIN", "Cincinnati Reds"), ("CLE", "Cleveland Guardians"),
        ("COL", "Colorado Rockies"), ("DET", "Detroit Tigers"),
        ("HOU", "Houston Astros"), ("KC", "Kansas City Royals"),
        ("LAA", "Los Angeles Angels"), ("LAD", "Los Angeles Dodgers"),
        ("MIA", "Miami Marlins"), ("MIL", "Milwaukee Brewers"),
        ("MIN", "Minnesota Twins"), ("NYM", "New York Mets"),
        ("NYY", "New York Yankees"), ("OAK", "Athletics"),
        ("PHI", "Philadelphia Phillies"), ("PIT", "Pittsburgh Pirates"),
        ("SD", "San Diego Padres"), ("SF", "San Francisco Giants"),
        ("SEA", "Seattle Mariners"), ("STL", "St. Louis Cardinals"),
        ("TB", "Tampa Bay Rays"), ("TEX", "Texas Rangers"),
        ("TOR", "Toronto Blue Jays"), ("WSH", "Washington Nationals"),
    ].map { LeagueTeam(abbr: $0.0, name: $0.1) }
}
