// Behavior checks for generation-time wording, document profiles and literal preferences.
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { analyzeText, validateWordList, DOCUMENT_TYPES } from "../ja-humanizer-check.mjs";

const checker = fileURLToPath(new URL("../ja-humanizer-check.mjs", import.meta.url));
const tmp = mkdtempSync(join(tmpdir(), "humanizer-generation-"));
let assertions = 0;
const hits = (text, id, options = {}) => analyzeText(text, options).findings.filter((f) => f.id === id);
const expect = (text, id, count, options = {}) => {
  assert.equal(hits(text, id, options).length, count, `${id}: ${text} ${JSON.stringify(options)}`);
  assertions += 1;
};
const cli = (args, input = "設定値を読み取ります。") => spawnSync(process.execPath, [checker, ...args], { input, encoding: "utf8" });
try {
  for (const text of ["データが壊れる。", "設定が壊れました。", "システムは静かに壊れる。", "アプリが壊れた。", "コードが壊れます。", "スキーマが壊れている。", "互換性が壊れる。"])
    expect(text, "vague-breakage", 1);
  for (const text of ["椅子が壊れる。", "サーバーのファンが壊れた。", "データの入った端末が壊れた。", "骨が折れる。", "更新後に設定値が初期値へ戻る。", "「データが壊れる」という表現を説明する。", '"データが壊れる"という表現。', "『システムが壊れる』を引用した。"])
    expect(text, "vague-breakage", 0);
  expect("地味`変数`に効く。", "vague-effect", 0);
  expect("データ`項目`が壊れる。", "vague-breakage", 0);
  expect("ゲ`値`ート", "project-word", 0, { wordList: { flag: ["ゲート"] } });
  expect("この設定が地味に効く。", "vague-effect", 1);
  expect("地味に効いてきます。", "vague-effect", 1);
  expect("薬が効く。", "vague-effect", 0);
  expect("「地味に効く」と書いた。", "vague-effect", 0);
  expect("もちろん、確認します。", "obvious-opener", 1);
  expect("確認します。もちろん、結果も返します。", "obvious-opener", 1);
  expect("もちろん確認します。", "obvious-opener", 0);
  expect("引用は「もちろん、確認します」です。", "obvious-opener", 0);
  expect("資料を、全員へ。", "copy-fragments", 1);
  expect("速い。軽い。安い。", "copy-fragments", 1);
  expect("資料を全員へ送ります。", "copy-fragments", 0);
  expect("速い。軽い。", "copy-fragments", 0);
  expect("## jqとは：使い方", "heading-colon", 1);
  expect("## [jqとは：使い方](https://example.com)", "heading-colon", 1);
  expect("## https://example.com/jqとは：使い方", "heading-colon", 0);
  expect("jqとは：使い方", "heading-colon", 0);

  const suspicious = "もちろん、データが壊れる。地味に効く。資料を、全員へ。速い。軽い。安い。";
  for (const protectedText of ["> " + suspicious, "`" + suspicious + "`", "```text\n" + suspicious + "\n```", "~~~text\n" + suspicious + "\n~~~", "---\ntitle: " + suspicious + "\n---", "| " + suspicious + " |", "<!-- ja-humanizer-disable-next-line -->\n" + suspicious]) {
    for (const id of ["vague-breakage", "vague-effect", "obvious-opener", "copy-fragments", "project-word"]) {
      expect(protectedText, id, 0, { wordList: { flag: ["データ"] } });
    }
  }
  // Exact-length CommonMark code delimiters, including backticks inside longer spans.
  for (const protectedText of [
    "``設定が壊れる `value` 地味に効く。``",
    "前 ``設定が壊れる `value`\n地味に効く。`` 後",
    "```設定が壊れる ``value`` 地味に効く。```",
    "````設定が壊れる ```value``` 地味に効く。````",
    "「引用の始まり\n設定が壊れる。地味に効く。\n引用の終わり」",
    "『引用\n設定が壊れる。地味に効く。』",
    "“引用\n設定が壊れる。地味に効く。”",
    "```text\n設定が壊れる。` 地味に効く。\n````",
  ]) {
    expect(protectedText, "vague-breakage", 0);
    expect(protectedText, "vague-effect", 0);
    expect(protectedText, "project-word", 0, { wordList: { flag: ["設定"] } });
  }
  for (const delimiter of ["`", "``", "```", "````"]) {
    expect(`${delimiter}設定が壊れる。${delimiter}設定が壊れる。`, "vague-breakage", 1);
    expect(`地味${delimiter}value${delimiter}に効く。`, "vague-effect", 0);
  }
  expect("「引用\n設定が壊れる。\n」設定が壊れる。", "vague-breakage", 1);
  assert.equal(hits("「引用\n設定が壊れる。\n」設定が壊れる。", "vague-breakage")[0].line, 3);
  expect("``設定が壊れる。`", "vague-breakage", 1);
  expect("`設定が壊れる。``", "vague-breakage", 1);
  expect("``設定が壊れる。", "vague-breakage", 1);
  expect("```設定が壊れる。``", "vague-breakage", 1);
  expect("````設定が壊れる。```", "vague-breakage", 1);
  expect("前 \\`設定が壊れる。`", "vague-breakage", 1);
  expect("前 `設定が壊れる。\\`設定が壊れる。", "vague-breakage", 1);
  const structured = "担当: 山田\n入力します。保存します。送信します。";
  expect(structured, "label-colon", 1);
  expect(structured, "uniform-endings", 1);
  for (const docType of ["spec", "minutes", "manual", "slides"]) {
    expect(structured, "label-colon", 0, { docType });
    expect(structured, "uniform-endings", 0, { docType });
  }
  expect(structured, "uniform-endings", 0, { docType: "mail" });
  expect("速い。軽い。安い。", "copy-fragments", 0, { docType: "slides" });
  expect("## 処理を止めます", "heading-sentence", 0, { docType: "slides" });
  for (const docType of ["pr", "incident", "article", "proposal", "mail", "manual", "spec", "minutes"]) {
    expect("速い。軽い。安い。", "copy-fragments", 1, { docType });
  }
  for (const docType of DOCUMENT_TYPES) {
    expect("要件を満たさない実装が原因です。", "circular-cause", 1, { docType, wordList: { allow: ["要件を満たさない実装が原因です。"] } });
    assert.equal(cli(["--doc-type", docType]).status, 0);
    assertions += 1;
  }
  const body = "地味に効く。別の場所では地味に効いた。";
  expect(body, "vague-effect", 1, { wordList: { allow: ["地味に効く"] } });
  expect("この一覧は地味に効く。", "vague-effect", 0, { wordList: { allow: ["この一覧は地味に効く"] } });
  expect("効くという語。地味に効く。", "vague-effect", 1, { wordList: { allow: ["効くという語"] } });
  expect("ゲートを通る。", "project-word", 1, { wordList: { flag: ["ゲート"] } });
  expect("品質ゲートを通る。", "project-word", 0, { wordList: { allow: ["品質ゲート"], flag: ["ゲート"] } });
  expect("品質ゲートとゲートを比べる。", "project-word", 1, { wordList: { allow: ["品質ゲート"], flag: ["ゲート"] } });
  expect("「ゲート」を引用する。", "project-word", 0, { wordList: { flag: ["ゲート"] } });
  expect("a.b と axb を比較する。", "project-word", 1, { wordList: { flag: ["a.b"] } });
  expect("a+b と ab を比較する。", "project-word", 1, { wordList: { flag: ["a+b"] } });
  expect("[ゲート](https://example.com/ゲート)", "project-word", 1, { wordList: { flag: ["ゲート"] } });
  expect("これは https://example.com/ゲート です。", "project-word", 0, { wordList: { flag: ["ゲート"] } });
  expect("要件を満たさない実装が原因です。", "circular-cause", 1, { wordList: { allow: ["要件を満たさない実装が原因です。"] } });
  for (const value of [null, [], "word", { extra: [] }, { allow: "word" }, { flag: [1] }, { allow: [""] }, { flag: [" "] }, { flag: ["a\nb"] }, { allow: null }, { flag: false }]) {
    assert.throws(() => validateWordList(value));
    const path = join(tmp, "invalid.json");
    writeFileSync(path, JSON.stringify(value));
    assert.equal(cli(["--word-list", path]).status, 2);
    assertions += 2;
  }
  assert.deepEqual(validateWordList({ flag: ["x", "x"] }), { allow: [], flag: ["x"] });
  assert.throws(() => analyzeText("本文", { docType: "unknown" }));
  for (const args of [["--doc-type", "unknown"], ["--doc-type"], ["--doc-type", "--json"], ["--word-list"], ["--word-list", "--json"], ["--word-list", join(tmp, "missing.json")], ["--unknown"]]) {
    const result = cli(args);
    assert.equal(result.status, 2, JSON.stringify(args));
    assert.match(result.stderr, /JA_HUMANIZER_CHECK_USAGE/u);
    assertions += 2;
  }
  const preferences = join(tmp, "words.json");
  writeFileSync(preferences, JSON.stringify({ allow: ["品質ゲート"], flag: ["ゲート"] }));
  const cliResult = cli(["--json", "--doc-type", "manual", "--word-list", preferences], "担当: 山田\n品質ゲートとゲートを確認します。");
  assert.equal(cliResult.status, 0);
  const result = JSON.parse(cliResult.stdout);
  assert.equal(result.findings.filter((f) => f.id === "project-word").length, 1);
  assert.equal(result.findings.filter((f) => f.id === "label-colon").length, 0);
  assertions += 3;
  writeFileSync(preferences, "{");
  assert.equal(cli(["--word-list", preferences]).status, 2);
  console.log(`JA_HUMANIZER_GENERATION_TEST_SUMMARY\tPASS\tassertions=${assertions}`);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
