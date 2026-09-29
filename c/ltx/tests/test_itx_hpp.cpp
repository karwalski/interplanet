/**
 * test_itx_hpp.cpp -- C++17 tests for the itx.hpp wrappers, focused on the
 * wire-format plan functions (itx::Json, makePlanIdJson, planHashJson,
 * validatePlanJson, reservedFieldCodeJson, canonicalJson, sha256Hex).
 *
 * Usage: test_itx_hpp [path/to/plan-ids.json]
 *        (default ../../spec/golden/plan-ids.json, i.e. run from c/ltx)
 */

#include "../include/itx.hpp"

#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>

static int passed = 0, failed = 0;

static void check(const std::string &name, bool cond) {
    if (cond) passed++;
    else { failed++; std::printf("FAIL: %s\n", name.c_str()); }
}

template <typename F>
static bool throwsInvalid(F f) {
    try { f(); } catch (const std::invalid_argument &) { return true; }
    return false;
}

static itx::JsonRef byName(itx::JsonRef vectors, const std::string &name) {
    for (std::size_t i = 0; i < vectors.size(); i++)
        if (vectors.at(i)["name"].str() == name) return vectors.at(i);
    return itx::JsonRef();
}

/** plan JSON with `,"key":value` appended (last key wins, first position). */
static std::string withField(const std::string &plan, const std::string &key, const std::string &value) {
    return plan.substr(0, plan.size() - 1) + ",\"" + key + "\":" + value + "}";
}

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "../../spec/golden/plan-ids.json";
    std::ifstream in(path, std::ios::binary);
    if (!in) { std::printf("cannot read %s\n", path); return 1; }
    std::stringstream ss;
    ss << in.rdbuf();

    const itx::Json golden = itx::Json::parse(ss.str());
    const itx::JsonRef vectors = golden["vectors"];

    std::printf("\n-- golden planId vectors (C++) --\n");
    check("golden vectors present", vectors.isArray() && vectors.size() >= 9);
    for (std::size_t i = 0; i < vectors.size(); i++) {
        itx::JsonRef gv = vectors.at(i);
        const std::string name = gv["name"].str().value_or("?");
        const std::string want = gv["planId"].str().value_or("");
        itx::JsonRef plan = gv["plan"];
        check("makePlanId(JsonRef) " + name, itx::makePlanId(plan) == want);
        const std::string text = plan.stringify();
        check("makePlanIdJson(text) " + name, itx::makePlanIdJson(text) == want);
        if (auto h = gv["planHash"].str()) {
            check("planHash(JsonRef) " + name, itx::planHash(plan) == *h);
            check("planHashJson(text) " + name, itx::planHashJson(text) == *h);
        }
        auto r = itx::validatePlan(plan);
        check("validatePlan accepts " + name, r.valid && r.errors.empty());
        check("validatePlanJson accepts " + name, itx::validatePlanJson(text).valid);
        check("no reserved field in " + name, !itx::reservedFieldCode(plan) && !itx::reservedFieldCodeJson(text));
    }
    check("v2 freeze anchor",
          byName(vectors, "v2-freeze-check")["planId"].str() == std::string("LTX-20260801-EARTHHQ-MARS-v2-d132e85d"));

    std::printf("\n-- JSON helpers --\n");
    check("canonicalJson sorts keys + JS numbers",
          itx::canonicalJson("{\"b\":[1e21,860.0],\"a\":null}") == "{\"a\":null,\"b\":[1e+21,860]}");
    check("canonicalJson throws on bad JSON", throwsInvalid([] { itx::canonicalJson("{"); }));
    check("Json::parse throws on trailing data", throwsInvalid([] { itx::Json::parse("{} x"); }));
    {
        itx::Json j = itx::Json::parse("{\"z\":1,\"a\":\"s\",\"n\":2.5}");
        check("stringify keeps insertion order", j.stringify() == "{\"z\":1,\"a\":\"s\",\"n\":2.5}");
        check("canonical sorts", j.canonical() == "{\"a\":\"s\",\"n\":2.5,\"z\":1}");
        check("object size + member key", j.root().size() == 3 && j.root().at(0).key() == "z");
        check("str / num accessors", j["a"].str() == std::string("s") && j["n"].num() == 2.5 && !j["a"].num());
        check("missing key is empty ref", !j["missing"] && !j["missing"].str());
        itx::Json moved = std::move(j);
        check("Json is movable", moved["z"].num() == 1.0);
    }
    check("sha256Hex(abc)",
          itx::sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    check("imul31Utf16 matches C", itx::imul31Utf16("abc") == itx_imul31_utf16("abc"));

    std::printf("\n-- validatePlan / reserved fields (C++) --\n");
    const std::string base = byName(vectors, "v3-upgrade-delays")["plan"].stringify();
    const std::string v2 = byName(vectors, "v2-freeze-check")["plan"].stringify();
    {
        auto r = itx::validatePlanJson(withField(base, "streams", "[{\"id\":\"S1\"}]"));
        check("non-empty streams rejected", !r.valid && r.hasCode("reserved_streams"));
        bool pathOk = false;
        for (const auto &e : r.errors)
            if (e.code == "reserved_streams") { pathOk = e.path == "streams" && !e.message.empty(); break; }
        check("streams error path + message", pathOk);
        check("reservedFieldCodeJson streams",
              itx::reservedFieldCodeJson(withField(base, "streams", "[{\"id\":\"S1\"}]")) == std::string("reserved_streams"));
    }
    check("empty streams ok on v3", itx::validatePlanJson(withField(base, "streams", "[]")).valid);
    {
        auto p = itx::Json::parse(withField(base, "branching", "{\"mode\":\"local\"}"));
        check("reservedFieldCode(JsonRef) branching", itx::reservedFieldCode(p) == std::string("reserved_branching"));
        check("validatePlan(JsonRef) branching", itx::validatePlan(p).hasCode("reserved_branching"));
    }
    check("v2 streams is v3 field", itx::validatePlanJson(withField(v2, "streams", "[]")).hasCode("v3_field_in_v2"));
    check("invalid JSON reports not_an_object", itx::validatePlanJson("{").hasCode("not_an_object"));
    check("validatePlan(empty ref) not_an_object", itx::validatePlan(itx::JsonRef()).hasCode("not_an_object"));
    check("makePlanIdJson throws on bad JSON", throwsInvalid([] { itx::makePlanIdJson("nope"); }));
    check("makePlanIdJson throws on v1 config", throwsInvalid([] { itx::makePlanIdJson("{\"v\":1}"); }));
    check("planHashJson throws on bad JSON", throwsInvalid([] { itx::planHashJson("["); }));

    std::printf("\n-- typed Plan wrapper --\n");
    {
        itx::Plan p = itx::createPlan("Golden Default", "2026-03-15T14:00:00.000Z", 840);
        check("typed makePlanId matches nodes-first vector",
              p.makePlanId() == byName(vectors, "v2-key-order-sensitive")["planId"].str());
        check("decodeHash round-trip", itx::decodeHash(p.encodeHash()).makePlanId() == p.makePlanId());
        check("DEFAULT_QUANTUM", itx::DEFAULT_QUANTUM == 5 && p.quantum() == 5);
    }

    std::printf("\n%d passed  %d failed\n", passed, failed);
    return failed ? 1 : 0;
}
