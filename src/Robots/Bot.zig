name: Name,
version: u32,
/// Many bots will announce as compatible with, this is that with.
requesting: ?Browser = null,

pub const unknown: Bot = .{
    .name = .unknown,
    .version = 0,
    .requesting = .unknown,
};
pub const malicious_bot: Bot = .{
    .name = .other_malicious,
    .version = 0,
};

const Bot = @This();

pub const Name = enum {
    /// LLM training set scraper
    /// ignores robots.txt
    abliterantbot,
    /// Hostile plagiarism bot
    academicbotrtu,
    /// closed SEO bot
    ahrefsbot,
    /// LLM model training set scraper
    /// aggressive
    /// ignores robots.txt
    amazonbot,
    /// very aggressive
    /// ignores robots.txt
    amzn_searchbot,
    /// AI answer scraper
    /// ignores robots.txt
    amzn_user,
    /// Very aggressive
    /// poorly maintained (fix your caching system)
    /// behaves like an LLM training set scraper
    applebot,
    /// Ignores robots.txt, but isn't considered malicious here because
    /// Archive.org has a reputation for going out of their way to be extremely
    /// ethical, and a good web citizen.
    archiveorgbot,
    /// Closed SEO bot
    backlinksextendedbot,
    /// Closed SEO bot
    barkrowler,
    /// Microsoft Bing search crawler
    /// Obviously unmaintained
    bingbot,
    /// Publicly brags about intentionally ignoring robots.txt
    /// note: witaf is wrong with you?!
    bravebot,
    /// Bytedance LLM model training set scraper, aggressive
    bytespider,
    /// LLM training set scraper, Common Crawl, (poorly maintained bot)
    ccbot,
    /// AI answer scraper
    claude_searchbot,
    /// LLM model scraping bot
    /// agressive
    claudebot,
    /// Closed SEO bot
    dataforseobot,
    /// Closed SEO bot
    /// Link/OpenGraph scanner. Allowed, and expected to ignore robots.tit
    discordbot,
    /// Closed SEO bot
    dotbot,
    /// Seems to be a search crawler
    duckduckbot,
    /// Extremely hostile crawler
    /// non-responsive to contact
    dxxsearch,
    /// LLM training set scraper
    /// https://elevenlabs.io/docs/bots
    /// buys/sells data, or crawls unidentified.
    elevenlabscrawler,
    /// LLM training set scraper
    /// Malformed UA
    epochal,
    /// LLM model training set scraper
    /// aggressive
    /// ignores robots.txt
    exasearchbot,
    /// The only actively maintained popular search crawler
    googlebot,
    /// LLM training set scraper
    googleother,
    /// LLM training set scraper
    gptbot,
    /// LLM search crawler
    /// ignores robots.txt
    keenable_user,
    /// LLM training set scraper
    /// ignores robots.txt
    /// Malformed UA
    keenablebot,
    /// Link/OpenGraph scanner for IRC clients
    /// Expected to ignore robots.txt
    lounge_irc_client,
    /// LLM training set scraper
    /// Repeatedly breaks in ways harmful to sites.
    metaexternalagent,
    // uh...?
    mj12bot,
    /// AI answer scraper
    /// persistent
    oai_searchbot,
    /// Implementation when unable to ID a bot with suspicious traffic.
    other_malicious,
    /// LLM training set scraper
    perplexitybot,
    /// LLM training/search scraper
    /// malformed UA
    /// non-responsive to contact
    reflectionbot,
    /// AI scraper
    /// malicious; (ignores robots.txt, repeated retries on 502)
    scrybot,
    /// Closed SEO bot (semrush) tries to evade robots.txt
    siteauditbot,
    /// Hobby bot?
    /// non-responsive to contact
    sleepbot,
    /// web search crawler https://www.sogou.com/docs/help/webmasters.htm#07
    /// Polite :)
    sogou_web_spider,
    /// non-responsive to contact
    techspybot,
    /// Closed SEO bot
    /// ignores robots.txt
    youbot,
    /// Closed SEO bot
    zoominfobot,

    unknown,

    pub fn isMalicious(n: Name) bool {
        return switch (n) {
            .abliterantbot => true, // ignores robots.txt
            .academicbotrtu => false,
            .ahrefsbot => false,
            .amazonbot => true,
            .amzn_searchbot => true, // ignores robots.txt
            .amzn_user => false,
            .applebot => false,
            .archiveorgbot => false,
            .backlinksextendedbot => false,
            .barkrowler => false,
            .bingbot => false,
            .bravebot => true,
            .bytespider => false,
            .ccbot => false,
            .claude_searchbot => true,
            .claudebot => true,
            .dataforseobot => false,
            .discordbot => false,
            .dotbot => false,
            .duckduckbot => false,
            .dxxsearch => true, // hyper aggressive
            .elevenlabscrawler => true, // buys data, or fails to ident
            .epochal => true, // malformed UA
            .exasearchbot => true,
            .googlebot => false,
            .googleother => false,
            .gptbot => false,
            .keenable_user => true,
            .keenablebot => true, //
            .lounge_irc_client => false,
            .metaexternalagent => true, // buggy crawler that can't behave
            .mj12bot => true,
            .oai_searchbot => false,
            .other_malicious => true,
            .perplexitybot => false,
            .reflectionbot => true, // sends broken data
            .scrybot => true, // non-responsive to contact
            .siteauditbot => false,
            .sleepbot => false,
            .sogou_web_spider => false,
            .techspybot => true, // non-responsive to contact
            .unknown => false, // assume good faith :/
            .youbot => true, // non-responsive to contact, ignores robots.txt
            .zoominfobot => false,
        };
    }

    pub fn seoBot(n: Name) bool {
        return switch (n) {
            .abliterantbot => false, // ignores robots.txt
            .academicbotrtu => true,
            .ahrefsbot => true,
            .amazonbot => false,
            .amzn_searchbot => true, // ignores robots.txt
            .amzn_user => false,
            .applebot => false,
            .archiveorgbot => false,
            .backlinksextendedbot => true,
            .barkrowler => true,
            .bingbot => false,
            .bravebot => true,
            .bytespider => true,
            .ccbot => false,
            .claude_searchbot => true,
            .claudebot => false,
            .dataforseobot => true,
            .dotbot => true,
            .duckduckbot => true,
            .dxxsearch => true,
            .elevenlabscrawler => true, // buys data, or fails to ident
            .epochal => true, // malformed UA
            .exasearchbot => true,
            .googlebot => false,
            .googleother => false,
            .gptbot => false,
            .keenable_user => false,
            .keenablebot => false,
            .metaexternalagent => false, // buggy crawler that can't behave
            .mj12bot => true,
            .oai_searchbot => false,
            .perplexitybot => false,
            .reflectionbot => false, // sends broken data
            .scrybot => true, // non-responsive to contact
            .siteauditbot => true,
            .sleepbot => true,
            .sogou_web_spider => false,
            .techspybot => true, // non-responsive to contact
            .youbot => true, // non-responsive to contact, ignores robots.txt
            .zoominfobot => true,

            // robots.txt doesn't apply so returns a friendly name
            .discordbot => false,
            .lounge_irc_client => false,
            .other_malicious => true,
            .unknown => false, // assume good faith :/
        };
    }

    pub fn llmScraper(n: Name) bool {
        return switch (n) {
            .abliterantbot => true, // ignores robots.txt
            .academicbotrtu => false,
            .ahrefsbot => false,
            .amazonbot => true,
            .amzn_searchbot => true, // ignores robots.txt
            .amzn_user => true,
            .applebot => false,
            .archiveorgbot => false,
            .backlinksextendedbot => false,
            .barkrowler => true,
            .bingbot => false,
            .bravebot => true,
            .bytespider => true,
            .ccbot => true,
            .claude_searchbot => true,
            .claudebot => true,
            .dataforseobot => false,
            .discordbot => false,
            .dotbot => true,
            .duckduckbot => false,
            .dxxsearch => true,
            .elevenlabscrawler => true, // buys data, or fails to ident
            .epochal => true, // malformed UA
            .exasearchbot => true,
            .googlebot => false,
            .googleother => true,
            .gptbot => true,
            .keenable_user => true,
            .keenablebot => true,
            .lounge_irc_client => false,
            .metaexternalagent => true, // buggy crawler that can't behave
            .mj12bot => true,
            .oai_searchbot => true,
            .other_malicious => true,
            .perplexitybot => true,
            .reflectionbot => true, // sends broken data
            .scrybot => true, // non-responsive to contact
            .siteauditbot => false,
            .sleepbot => true,
            .sogou_web_spider => true,
            .techspybot => true, // non-responsive to contact
            .youbot => true, // non-responsive to contact, ignores robots.txt
            .zoominfobot => false,

            .unknown => false, // assume good faith :/
        };
    }

    pub fn robotsTxtName(n: Name) [:0]const u8 {
        return switch (n) {
            .abliterantbot => "AbliterantBot",
            .academicbotrtu => "AcademicBotRTU",
            .ahrefsbot => "AhrefsBot",
            .amazonbot => "Amazonbot",
            .amzn_searchbot => "Amzn-SearchBot",
            .amzn_user => "Amzn-User",
            .applebot => "Applebot",
            .archiveorgbot => "archive.org_bot",
            .backlinksextendedbot => "BacklinksExtendedBot",
            .barkrowler => "Barkrowler",
            .bingbot => "Bingbot",
            .bravebot => "Bravebot",
            .bytespider => "Bytespider",
            .ccbot => "CCBot",
            .claude_searchbot => "Claude-SearchBot",
            .claudebot => "ClaudeBot",
            .dataforseobot => "DataForSeoBot",
            .dotbot => "DotBot",
            .duckduckbot => "DuckDuckBot",
            .dxxsearch => "DXXSearch",
            .elevenlabscrawler => "ElevenlabsCrawler",
            .epochal => "Epochal-Search",
            .exasearchbot => "ExaSearchBot",
            .googlebot => "GoogleBot",
            .googleother => "GoogleOther",
            .gptbot => "GPTBot",
            .keenable_user => "Keenable-User",
            .keenablebot => "KeenableBot",
            .metaexternalagent => "meta-externalagent",
            .mj12bot => "MJ12bot",
            .oai_searchbot => "OAI-SearchBot",
            .perplexitybot => "PerplexityBot",
            .reflectionbot => "Reflectionbot",
            .scrybot => "ScryBot",
            .siteauditbot => "SiteAuditBot",
            .sleepbot => "SleepBot",
            .sogou_web_spider => "Sogou web spider", // sourced from https://www.sogou.com/robots.txt
            .techspybot => "TechSpyBot",
            .youbot => "YouBot",
            .zoominfobot => "ZoominfoBot",

            // robots.txt doesn't apply so returns a friendly name
            .discordbot => "DiscordBot",
            .lounge_irc_client => "Lounge (IRC helper)",
            .other_malicious => "Malicious Bot",
            .unknown => "Other Unknown Bot",
        };
    }

    pub fn obeysCrawlDelay(comptime name: Name) bool {
        return switch (name) {
            .abliterantbot => false, // ignores robots
            .academicbotrtu => false, // TODO
            .ahrefsbot => false, // TODO
            .amazonbot => false, // TODO
            .amzn_searchbot => false,
            .amzn_user => false, // TODO
            .applebot => false,
            .backlinksextendedbot => false, // TODO
            .barkrowler => false, // TODO
            .bingbot => false,
            .bravebot => false, // TODO
            .bytespider => false, // TODO
            .ccbot => false, // TODO
            .claude_searchbot => false,
            .claudebot => false,
            .dataforseobot => false, // TODO
            .dotbot => false, // TODO
            .duckduckbot => false, // TODO
            .dxxsearch => false, // TODO
            .exasearchbot => false, // TODO
            .googlebot => false,
            .googleother => false,
            .gptbot => false,
            .keenable_user => false, // TODO
            .keenablebot => false, // ignores robots.txt
            .metaexternalagent => false,
            .mj12bot => false, // TODO
            .oai_searchbot => false, // TODO
            .other_malicious => false,
            .other_malicious => false,
            .perplexitybot => false, // TODO
            .scrybot => false,
            .siteauditbot => false, // TODO
            .sleepbot => false, // TODO
            .sogou_web_spider => true,
            .techspybot => false,
            .youbot => false,

            .archiveorgbot => true, // allowed to ignore robots
            .discordbot => false, // Allowed to ignore robots.txt
            .lounge_irc_client => false,
            .unknown => false,
        };
    }

    pub fn verIdent(comptime name: Name) ?[]const u8 {
        return switch (name) {
            .abliterantbot => "AbliterantBot/",
            .academicbotrtu => null, // TODO
            .ahrefsbot => null, // TODO
            .amazonbot => null, // TODO
            .amzn_searchbot => "Amzn-SearchBot/",
            .amzn_user => null, // TODO
            .applebot => "Applebot/",
            .backlinksextendedbot => null, // TODO
            .barkrowler => null, // TODO
            .bingbot => "bingbot/",
            .bravebot => null, // TODO
            .bytespider => null, // TODO
            .ccbot => null, // TODO
            .claude_searchbot => "Claude-SearchBot/",
            .claudebot => "ClaudeBot/",
            .dataforseobot => null, // TODO
            .discordbot => "Discordbot/",
            .dotbot => null, // TODO
            .duckduckbot => null, // TODO
            .dxxsearch => null, // TODO
            .elevenlabscrawler => "ElevenlabsCrawler/",
            .epochal => "Epochal-Search/",
            .exasearchbot => null, // TODO
            .googlebot => "Googlebot/",
            .googleother => null,
            .gptbot => "GPTBot/",
            .keenable_user => null, // TODO
            .keenablebot => "KeenableBot/",
            .lounge_irc_client => null,
            .metaexternalagent => null,
            .mj12bot => null, // TODO
            .oai_searchbot => null, // TODO
            .perplexitybot => null, // TODO
            .reflectionbot => "Reflectionbot/",
            .scrybot => "ScryBot/",
            .siteauditbot => null, // TODO
            .sleepbot => null, // TODO
            .sogou_web_spider => "Sogou web spider/",
            .techspybot => "TechSpyBot/",
            .youbot => "YouBot/",
            .zoominfobot => null, // TODO

            .other_malicious => null,
            .archiveorgbot => null,
            .unknown => null,
        };
    }

    pub fn ident(comptime name: Name, str: []const u8) bool {
        return switch (name) {
            .abliterantbot => find(u8, str, "AbliterantBot/0.1 (+https://abliterant.ai)") != null,
            .academicbotrtu => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .ahrefsbot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .amazonbot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .amzn_searchbot => find(u8, str, "Amzn-SearchBot/") != null,
            .amzn_user => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .applebot => endsWith(u8, str, "Applebot/0.1; +http://www.apple.com/go/applebot)"),
            .backlinksextendedbot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .barkrowler => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .bingbot => find(u8, str, "compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)") != null,
            .bravebot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .bytespider => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .ccbot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .claude_searchbot => endsWith(u8, str, "compatible; Claude-SearchBot/1.0; +claudebot@anthropic.com)"),
            .claudebot => endsWith(u8, str, "compatible; ClaudeBot/1.0; +claudebot@anthropic.com)"),
            .dataforseobot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .discordbot => eql(u8, str, "Mozilla/5.0 (compatible; Discordbot/2.0; +https://discordapp.com)"),
            .dotbot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .duckduckbot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .dxxsearch => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .elevenlabscrawler => find(u8, str, "ElevenlabsCrawler") != null,
            .epochal => find(u8, str, "Epochal") != null,
            .exasearchbot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .googlebot => endsWith(u8, str, "Googlebot/2.1; +http://www.google.com/bot.html)"),
            .googleother => endsWith(u8, str, "GoogleOther"),
            .gptbot => endsWith(u8, str, "compatible; GPTBot/1.2; +https://openai.com/gptbot)"),
            .keenable_user => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .keenablebot => find(u8, str, "KeenableBot/") != null,
            .lounge_irc_client => eql(u8, str, "Mozilla/5.0 (compatible; The Lounge IRC Client; +https://github.com/thelounge/thelounge) facebookexternalhit/1.1 Twitterbot/1.0"),
            .metaexternalagent => eql(u8, str, "meta-externalagent/1.1 (+https://developers.facebook.com/docs/sharing/webmasters/crawler)"),
            .mj12bot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .oai_searchbot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .perplexitybot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .reflectionbot => find(u8, str, "Mozilla/5.0 (compatible; Reflectionbot/1.0; +https://reflection.ai/bot)") != null,
            .scrybot => startsWith(u8, str, "ScryBot/1.0 (+https://scry.io; ethical public-content crawler)"),
            .siteauditbot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .sleepbot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search
            .sogou_web_spider => find(u8, str, "Sogou web spider/") != null,
            .techspybot => find(u8, str, "Mozilla/5.0 (compatible; Reflectionbot/1.0; +https://reflection.ai/bot)") != null,
            .youbot => startsWith(u8, str, "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; YouBot/1.0"),
            .zoominfobot => find(u8, str, comptime name.robotsTxtName()) != null, // TODO improve search

            .other_malicious => false,
            .unknown => false,
            .archiveorgbot => false,
        };
    }

    test {
        _ = &std.testing.refAllDecls(@This());
        _ = obeysCrawlDelay;
    }
};

pub fn resolve(str: []const u8) ?Bot {
    const E = @typeInfo(Name).@"enum";
    inline for (E.field_values) |bot_int| {
        const name: Name = @fromBackingInt(bot_int);
        if (Name.ident(name, str)) {
            const version_id = comptime name.verIdent();
            if (version_id) |vid| {
                return .{ .name = name, .version = parseVersion(str, vid) catch 0 };
            } else return .{ .name = name, .version = 0 };
        }
    }

    return null;
}

fn parseVersion(str: []const u8, comptime target: []const u8) error{Invalid}!u32 {
    if (find(u8, str, target)) |idx| {
        const start = idx + target.len;
        // 3 is the minimum reasonable tail for a version
        if (str.len < start + 3) return error.Invalid;
        const end = findScalarPos(u8, str, start, '.') orelse return error.Invalid;
        return parseInt(u32, str[start..end], 10) catch return error.Invalid;
    } else return error.Invalid;
}

pub const rules = struct {
    pub const all: []const Robots.RuleFn = &.{
        rules.knownSubnet,
        rules.expectedLanguages,
        rules.expectedParamDepth,
    };

    pub fn rfc9110_10_1_2(ua: UserAgent, r: *const Request, score: *f16) void {
        // https://www.rfc-editor.org/rfc/rfc9110#section-10.1.2

        _ = ua;
        _ = r;
        _ = score;
        if (false) {}
    }

    pub fn knownSubnet(ua: UserAgent, r: *const Request, score: *f16) void {
        if (ua.agent != .bot) return;

        if (bots.get(ua.agent.bot.name).network) |nw| {
            for (nw.nets) |net| {
                if (startsWith(u8, r.remote_addr, net)) break;
            } else {
                if (nw.exaustive) score.* = @max(score.*, 1.0);
            }
        }
    }

    /// Experimental rule that has high strength as a heuristic. Currently
    /// unimplemented as without a feedback mechanism it's specificity is too
    /// low, and introduces unwelcome bias & noise.
    pub fn expectedLanguages(ua: UserAgent, r: *const Request, score: *f16) void {
        _ = ua;
        _ = r;
        _ = score;
    }

    pub fn expectedParamDepth(ua: UserAgent, r: *const Request, score: *f16) void {
        acceptEncodingDepth(ua, r, score);
    }

    /// All browsers accept all 4 (order is high signal as well)
    fn acceptEncodingDepth(_: UserAgent, r: *const Request, score: *f16) void {
        var add: f16 = 0.3;

        if (r.accept.encoding) |encode| {
            if (encode.br) add -= 0.1;
            if (encode.deflate) add -= 0.1;
            if (encode.zstd) add -= 0.1;
            if (encode.gzip) add -= 0.1;
        } else add += 1.0;

        score.* = score.* + add;
    }

    fn secClientHints(ua: UserAgent, r: *const Request, score: *f16) void {
        secClientHintsUA(ua, r, score);
    }

    fn secClientHintsUA(_: UserAgent, r: *const Request, score: *f16) void {
        if (r.headers.getCustom("HTTP_SEC_CH_UA")) |list| {
            if (list.list.items.len > 1) {
                score.* +|= 0.5;
                return;
            }
            if (startsWith(u8, list.list.items[0], "\"Not_A Brand\";v=\"")) {
                score.* +|= 0.5;
            }
        }
    }
};

/// This isn't the final implementation, I'm just demoing some ideas
pub const Network = struct {
    nets: []const []const u8,
    exaustive: bool = true,

    pub const cloud_gcp: Network = .{
        .nets = &.{
            "35.224.0.0/12",
            "35.240.0.0/13",
            "35.208.0.0/12",
        },
        .exaustive = false,
    };
};

pub const Identity = struct {
    bot: Bot.Name,
    network: ?Network,
};

pub const bots: std.EnumArray(Name, Identity) = .{
    .values = [@typeInfo(Name).@"enum".field_names.len]Identity{
        .{ .bot = .abliterantbot, .network = null },
        .{ .bot = .academicbotrtu, .network = null },
        .{ .bot = .ahrefsbot, .network = null },
        .{ .bot = .amazonbot, .network = null },
        .{ .bot = .amzn_searchbot, .network = null },
        .{ .bot = .amzn_user, .network = null },
        .{ .bot = .applebot, .network = null },
        .{ .bot = .archiveorgbot, .network = null },
        .{ .bot = .backlinksextendedbot, .network = null },
        .{ .bot = .barkrowler, .network = null },
        .{ .bot = .bingbot, .network = null },
        .{ .bot = .bravebot, .network = null },
        .{ .bot = .bytespider, .network = null },
        .{ .bot = .ccbot, .network = null },
        .{ .bot = .claude_searchbot, .network = null },
        .{ .bot = .claudebot, .network = null },
        .{ .bot = .dataforseobot, .network = null },
        .{ .bot = .discordbot, .network = .cloud_gcp },
        .{ .bot = .dotbot, .network = null },
        .{ .bot = .duckduckbot, .network = null },
        .{ .bot = .dxxsearch, .network = null },
        .{ .bot = .elevenlabscrawler, .network = null },
        .{ .bot = .epochal, .network = null },
        .{ .bot = .exasearchbot, .network = null },
        .{ .bot = .googlebot, .network = .{ .nets = &[_][]const u8{"66.249"} } },
        .{ .bot = .googleother, .network = .{ .nets = &[_][]const u8{"66.249"} } },
        .{ .bot = .gptbot, .network = .{ .nets = &[_][]const u8{"74.7.227"} } }, // incomplete ip list
        .{ .bot = .keenable_user, .network = null },
        .{ .bot = .keenablebot, .network = null }, // published on their site, but they're malicious
        .{ .bot = .lounge_irc_client, .network = null },
        .{ .bot = .metaexternalagent, .network = null },
        .{ .bot = .mj12bot, .network = null },
        .{ .bot = .oai_searchbot, .network = null },
        .{ .bot = .other_malicious, .network = null },
        .{ .bot = .perplexitybot, .network = null },
        .{ .bot = .reflectionbot, .network = null },
        .{ .bot = .scrybot, .network = null },
        .{ .bot = .siteauditbot, .network = null },
        .{ .bot = .sleepbot, .network = null },
        .{ .bot = .sogou_web_spider, .network = null },
        .{ .bot = .techspybot, .network = null },
        .{ .bot = .youbot, .network = .{ .nets = &[_][]const u8{"68.67.112"} } }, // incomplete ip list
        .{ .bot = .zoominfobot, .network = null },

        // Split ordering

        .{ .bot = .unknown, .network = null },
    },
};

test {
    _ = &std.testing.refAllDecls(@This());
}

test "bot ident order" {
    const E = @typeInfo(Bot.Name).@"enum";
    inline for (E.field_values) |value| {
        const bot_: Bot.Name = @fromBackingInt(@intCast(value));
        try std.testing.expectEqual(bot_, bots.get(bot_).bot);
    }
}

const Browser = @import("Browser.zig");
const Request = @import("../Request.zig");
const Robots = @import("../Robots.zig");
const UserAgent = @import("../UserAgent.zig");
const std = @import("std");
const endsWith = std.mem.endsWith;
const eql = std.mem.eql;
const find = std.mem.find;
const findScalarPos = std.mem.findScalarPos;
const startsWith = std.mem.startsWith;
const parseInt = std.fmt.parseInt;
