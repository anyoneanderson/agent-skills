#!/usr/bin/env node
// ja-humanizer-check.mjs — mechanical detector for AI tells in Japanese prose.
//
// It counts what a regular expression can count: label-plus-colon bullets,
// runs of identical sentence endings, sentence-length uniformity, Tier 1
// vocabulary, chained requests, causes that restate the symptom, generic
// countermeasures, and a missing estimate next to a request to choose.
// Everything that needs judgement (whether a contrast corrects a real belief,
// whether a sentence is thin for this reader) stays with the skill host.
//
// The "concrete action" allowance mirrors ~/.agents/hooks/language-lint.mjs:
// a sentence that already names an operation (store, compare, send, reject,
// stop ...) is not reported for an abstract verb.
//
// Usage:
//   node ja-humanizer-check.mjs [--json] [--warn] [--mode article|mail|argument|narrative] FILE...
//   cat text.md | node ja-humanizer-check.mjs [--json] [--warn]
// Exit: 0 = no Tier 1 finding (or --warn) | 1 = Tier 1 finding present | 2 = usage error

import { realpathSync } from "node:fs";
import { readFile } from "node:fs/promises";
import process from "node:process";
import { pathToFileURL } from "node:url";

const CONCRETE_ACTION = /保存|記録|格納|送信|通知|返却|返す|渡す|比較|計算|更新|削除|取得|読み込|書き込|呼び出|拒否|停止|検査|検証|変換|生成|作成|実行|公開|表示|追加|含め|判定|許可|設定|入力|出力|登録|接続|起動|終了|集計|測定|可視化|依頼|報告|確認/u;
const DISABLE_NEXT_LINE = /<!--\s*ja-humanizer-disable-next-line(?:\s+[^>]*)?-->/iu;

// Tier 1 vocabulary. Each entry is reported unless the same sentence names a concrete action.
const ABSTRACT_VERBS = [
  { label: "写像する", pattern: /写像(?:する|し|した|して|され|させ)/u },
  { label: "束縛する", pattern: /束縛(?:する|し|した|して|され|させ)/u },
  { label: "安全側へ倒す", pattern: /安全側(?:へ|に)倒(?:す|し|した|して|され)/u },
  { label: "収束させる", pattern: /収束(?:させる|させ|する|し|した|して)/u },
  { label: "配る", pattern: /(?:を|で)配(?:る|り|った|って)(?!当|布|置|送|信)/u },
  { label: "閉じる", pattern: /(?:を|全体を)閉(?:じる|じ|じた|じて)/u },
  { label: "噛ませる", pattern: /噛ませ(?:る|た|て)/u },
  { label: "倒す", pattern: /(?:へ|に)倒(?:す|し|した|して)(?!れ)/u },
  { label: "担保する", pattern: /担保(?:する|し|した|して|され)/u },
  { label: "実現する", pattern: /(?:を|が)実現(?:する|し|した|して|され|します|できます)/u },
  { label: "可能にする", pattern: /を可能に(?:する|し|した|して|します)/u },
  { label: "寄与する", pattern: /に寄与(?:する|し|した|して|します)/u },
  { label: "担う", pattern: /(?:を|役割を)担(?:う|い|った|って|います)/u },
];

const STAGING = [
  { label: "静かに", pattern: /静かに(?:切り替わ|変わ|進|動|始ま)/u },
  { label: "最重要", pattern: /最重要/u },
  { label: "感覚ではなく", pattern: /感覚ではなく/u },
  { label: "同じ週に", pattern: /^同じ(?:週|日|月)に、?/u },
  { label: "賢さではなく", pattern: /(?:賢さ|速さ|数)ではなく[「『]?[^。]{1,12}[」』]?です/u },
];

const THREAT_CLOSER = /(?:この(?:数字|数値|情報|実績)がないと|がなければ)[^。]*(?:できません|判断できない|手遅れ)|手遅れになります/u;

const CUSHION = [
  { label: "ご理解いただけますと幸いです", pattern: /ご理解(?:いただけますと|いただけると|賜りますよう)/u },
  { label: "大変恐縮ですが", pattern: /大変恐縮(?:ですが|ではございますが)/u },
  { label: "諸般の事情", pattern: /諸般の事情/u },
  { label: "お手数をおかけしますが", pattern: /お手数(?:を)?おかけ(?:します|いたします)が/u },
  { label: "差し支えなければ", pattern: /差し支えなければ/u },
];

const CHAINED_REQUEST = /(?:ようでしたら|ようであれば|でしたら|であれば|の場合は|のであれば)[^。]{0,60}(?:お願いできますでしょうか|お願いできますか|いただけますでしょうか|いただけますか|お願いいたします|お願いします)/u;

const EVALUATIVE = /削減|向上|改善|容易に|迅速|柔軟|魅力|効率|最適|簡単に|短期間で|低減|優しい|スムーズ/u;
const EVALUATIVE_CLOSER = /点も魅力です|が魅力です|メリットがあります|が期待できます/u;
const SPECIFIC = /[0-9０-９]|[一二三四五六七八九十百千万]+(?:台|件|社|日|人|回|分|秒|時間|円|割|％|%)|[（(][^）)]{2,}[）)]|「[^」]{2,}」/u;
const ENUMERATION = /[^、]+(?:や|と)[^、]+、[^、]+(?:など|等|といった|のような)/u;

const TEMPLATE_OPENER = /^(?:近年|昨今|現代では)[、,]?[^。]*(?:注目|進化|重要|普及)|本記事では[^。]*(?:解説|紹介|説明)|をご存[じ知]でしょうか/u;
const TEMPLATE_CLOSER = /(?:が期待されます|が期待されています|今後の展開が注目されます|と言えるでしょう|といえるでしょう|ではないでしょうか)。?$/u;
const SURU_KOTO_GA_DEKIMASU = /することができ(?:ます|る|ません)/u;
const EMPTY_ADVERB = /(?:確実に|本質的に|シンプルに|適切に|柔軟に|明確に|大きく)(?:進|変|向上|改善|対応|管理|把握|整理)/u;
const TRIAD = /(?:[3３三]つ|[3３三]点|[3３三]種類)(?:の|あります|です|に)/gu;
const GENERIC_MEASURE = /徹底|こまめ|意識(?:する|して|を高め)|強化|注意(?:する|して)|共有を/u;
const MEASURE_TRIGGER = /(?:場合|とき|際|時)(?:に|は|の)|に対する|に対して|発生した|変更(?:が|の)(?:あった|入った|生じ)|ごとに|前に|後に/u;
const CIRCULAR_CAUSE = /要件を(?:満足|満た)(?:しない|さない|していない)(?:実装|開発|内容)[^。]*(?:原因|要因)/u;
// A request to choose is only counted when the text actually lays out alternatives.
const CHOICE_REQUEST = /どちらの(?:方針|案|対応)|いずれの(?:方針|案|対応)|選択肢が考えられます|案[1-9１-９]/u;
const CHOICE_OPTIONS = /(?:^|\n)\s*(?:[・\-*]|対応案|案[1-9１-９]|[1-9１-９][.．)）])/gu;
// A condition that is a real prerequisite (consent, approval, validity) must stay; only a condition that
// merely waits for the answer to a question already asked is a chained request.
const PRECONDITION = /同意|承諾|承認|許可|権限|有効|お持ち|問題なければ|問題がなければ|差し支えなければ|ご確認(?:が取れ|いただけ|でき)|完了(?:し|され)|届き|受領/u;
const ESTIMATE = /[0-9０-９〇一二三四五六七八九十]+(?:営業日|日|週間|時間|か月|ヶ月|カ月)|期限|納期|見込み|まで(?:に)?(?:完了|対応|納品)/u;
const TADASHI = /^(?:ただし|但し)[、,]?/u;
const REASON = /ので|ため|から|につき|ゆえ/u;
const HEADING_AS_SENTENCE = /(?:した|きた|なった|動いた|変わった|揃った|ます|です|である|だ|ない)[。！!]?$/u;

const QUESTIONS = {
  "thin-claim": {
    ja: "この項目で、何が不要になり、以前はどうで、なぜそうなるのかを教えてください。",
    en: "For this item, what becomes unnecessary, what was it like before, and why does it happen?",
  },
  "cause-restates-symptom": {
    ja: "原因欄が経緯の言い換えになっています。いつ、誰が、何を知らずに、何をしたかを教えてください。",
    en: "The cause restates the symptom. When, who, not knowing what, did what?",
  },
  "circular-cause": {
    ja: "「要件を満たさない実装が原因」は不具合の定義そのものです。どの工程で何が抜けたのかを教えてください。",
    en: "'An implementation that missed the requirement' is the definition of the bug. Which step dropped what?",
  },
  "generic-measure": {
    ja: "対策が一般語だけです。原因のどの工程に、どんな条件で、何を追加するのかを教えてください。",
    en: "The countermeasure is generic words only. Which step of the cause does it close, under what trigger, by adding what?",
  },
  "missing-estimate": {
    ja: "相手に選択を求めていますが、日数か期限がありません。見込みを教えてください。",
    en: "You ask the recipient to choose, but there is no duration or deadline. What is the estimate?",
  },
};

function stripInlineCode(line) {
  return line.replace(/`[^`]*`/gu, "");
}

function splitSentences(text) {
  return text.split(/(?<=[。！？!?])/u).map((s) => s.trim()).filter(Boolean);
}

function sentenceEnding(sentence) {
  const s = sentence.replace(/[。！？!?]$/u, "");
  const m = s.match(/(できます|ています|ております|ます|です|でした|ません|ください|ですね|でしょう)$/u);
  return m ? m[1] : null;
}

function isSectionHeading(line) {
  return /^#{1,6}\s/u.test(line) || /^[・■●【]/u.test(line) || /^\S{1,20}[:：]$/u.test(line);
}

export function lintText(text, { source = "text", mode = "argument", lang = "ja" } = {}) {
  const findings = [];
  const lines = String(text).split(/\r?\n/u);
  let fenced = false;
  let inFrontmatter = false;
  let disableNext = false;
  const prose = []; // { line, text }
  const push = (tier, id, line, message, extra = {}) => {
    findings.push({ tier, id, source, line, message, ...extra });
  };
  const question = (id) => (QUESTIONS[id] ? QUESTIONS[id][lang === "en" ? "en" : "ja"] : undefined);

  lines.forEach((raw, index) => {
    const lineNo = index + 1;
    const trimmed = raw.trim();
    if (index === 0 && trimmed === "---") { inFrontmatter = true; return; }
    if (inFrontmatter) { if (trimmed === "---") inFrontmatter = false; return; }
    if (/^(```|~~~)/u.test(trimmed)) { fenced = !fenced; return; }
    if (fenced) return;
    if (DISABLE_NEXT_LINE.test(raw)) { disableNext = true; return; }
    if (disableNext) { disableNext = false; return; }
    const cleaned = stripInlineCode(raw).replace(/<!--.*?-->/gu, "").trim();
    if (!cleaned) return;
    if (/^\|.*\|$/u.test(cleaned)) return;
    prose.push({ line: lineNo, text: cleaned });
  });

  // Line-level patterns.
  for (const { line, text } of prose) {
    const boldLabel = /^\s*(?:[-*・]\s*)?\*\*[^*]+\*\*\s*[:：]/u.test(text);
    const plainLabel = /^(?:[-*・]\s*)?[^\s:：]{1,24}[:：]\s*\S*$/u.test(text) && !/[0-9０-９][:：][0-9０-９]/u.test(text) && !/https?:/u.test(text) && !/^#{1,6}\s/u.test(text);
    if (boldLabel || plainLabel) {
      push(mode === "article" || mode === "narrative" ? 3 : 2, "label-colon", line, "label-plus-colon item");
    }
    if (/^#{1,6}\s/u.test(text)) {
      const heading = text.replace(/^#{1,6}\s+/u, "").replace(/[0-9０-９.．]+\s*/u, "");
      if (HEADING_AS_SENTENCE.test(heading)) push(2, "heading-sentence", line, "heading written as a sentence");
    }
    if (TEMPLATE_OPENER.test(text)) push(2, "template-opener", line, "template opener");
    if (TEMPLATE_CLOSER.test(text)) push(2, "template-closer", line, "template closer");
    if (SURU_KOTO_GA_DEKIMASU.test(text)) push(2, "suru-koto-ga-dekimasu", line, "することができます");
    if (EMPTY_ADVERB.test(text)) push(2, "empty-adverb", line, "empty adverb");
    if (THREAT_CLOSER.test(text)) push(1, "threat-closer", line, "threatening closer; state the premise instead");
    if (CIRCULAR_CAUSE.test(text)) push(1, "circular-cause", line, "cause is the definition of the defect", { question: question("circular-cause") });

    for (const sentence of splitSentences(text)) {
      const hasConcrete = CONCRETE_ACTION.test(sentence);
      for (const term of ABSTRACT_VERBS) {
        if (term.pattern.test(sentence) && !hasConcrete) push(1, "abstract-verb", line, `abstract verb: ${term.label}`);
      }
      for (const term of STAGING) {
        if (term.pattern.test(sentence)) push(1, "staging", line, `staging word: ${term.label}`);
      }
      for (const term of CUSHION) {
        if (term.pattern.test(sentence)) push(1, "cushion", line, `cushion phrase: ${term.label}`);
      }
      if (TADASHI.test(sentence) && !REASON.test(sentence)) push(2, "tadashi-no-reason", line, "「ただし」 without a reason");
      if (EVALUATIVE_CLOSER.test(sentence)) push(1, "thin-claim", line, "evaluative closer without a fact", { question: question("thin-claim") });
    }
  }

  // Thin items: a label-plus-colon item (label line, body on the same or next line) built on evaluative words with no specifics.
  for (let i = 0; i < prose.length; i += 1) {
    const cur = prose[i];
    const isLabel = /^(?:[-*・]\s*)?[^\s:：]{1,24}[:：]\s*$/u.test(cur.text) || /^(?:[-*・]\s*)?\*\*[^*]+\*\*\s*[:：]/u.test(cur.text);
    if (!isLabel) continue;
    const body = /[:：]\s*$/u.test(cur.text) ? (prose[i + 1]?.text ?? "") : cur.text.replace(/^.*?[:：]\s*/u, "");
    if (!body) continue;
    const labelText = cur.text.replace(/\*\*/gu, "");
    const evaluative = EVALUATIVE.test(labelText) || EVALUATIVE.test(body);
    if (evaluative && !SPECIFIC.test(body) && !ENUMERATION.test(body)) {
      push(1, "thin-claim", cur.line, "item rests on evaluative words with no specifics", { question: question("thin-claim") });
    }
  }

  // Section-level checks: cause vs events, countermeasures, estimate.
  const sections = [];
  let current = { heading: "", line: 0, body: [] };
  for (const { line, text } of prose) {
    if (isSectionHeading(text)) {
      sections.push(current);
      current = { heading: text.replace(/^#{1,6}\s+|^[・■●【]\s*|[】:：]\s*$/gu, ""), line, body: [] };
    } else {
      current.body.push(text);
    }
  }
  sections.push(current);
  const bigrams = (s) => {
    const chars = s.replace(/[\s、。「」（）()・:：]/gu, "");
    const set = new Set();
    for (let i = 0; i < chars.length - 1; i += 1) set.add(chars.slice(i, i + 2));
    return set;
  };
  const events = sections.find((s) => /経緯|事象|現象|発生/u.test(s.heading));
  const cause = sections.find((s) => /原因|要因/u.test(s.heading));
  if (events && cause && cause.body.length > 0) {
    const e = bigrams(events.body.join(""));
    const c = bigrams(cause.body.join(""));
    let shared = 0;
    for (const g of c) if (e.has(g)) shared += 1;
    const ratio = c.size === 0 ? 0 : shared / c.size;
    if (ratio >= 0.45) push(1, "cause-restates-symptom", cause.line, `cause section shares ${Math.round(ratio * 100)}% of its bigrams with the events section`, { question: question("cause-restates-symptom") });
  }
  const measure = sections.find((s) => /再発防止|対策|改善策|防止策/u.test(s.heading));
  if (measure) {
    const body = measure.body.join("");
    if (GENERIC_MEASURE.test(body) && !MEASURE_TRIGGER.test(body)) {
      push(1, "generic-measure", measure.line, "countermeasure is generic words with no trigger condition", { question: question("generic-measure") });
    }
  }
  const whole = prose.map((p) => p.text).join("\n");
  const optionCount = (whole.match(CHOICE_OPTIONS) ?? []).length;
  if (CHOICE_REQUEST.test(whole) && optionCount >= 2 && !ESTIMATE.test(whole)) {
    const at = prose.find((p) => CHOICE_REQUEST.test(p.text))?.line ?? 1;
    push(1, "missing-estimate", at, "asks the recipient to choose but gives no duration or deadline", { question: question("missing-estimate") });
  }

  const paragraphs = [];
  let para = [];
  for (const { line, text } of prose) {
    if (isSectionHeading(text) || text === "") { if (para.length) paragraphs.push(para); para = []; continue; }
    for (const s of splitSentences(text)) para.push({ line, s });
  }
  if (para.length) paragraphs.push(para);

  // Chained requests: a conditional request whose condition rests on a question the text has just asked.
  for (const p of paragraphs) {
    for (let i = 0; i < p.length; i += 1) {
      const { line, s } = p[i];
      if (!CHAINED_REQUEST.test(s)) continue;
      const prev = p[i - 1]?.s ?? "";
      const refersToQuestion = /上記|前述|先述|先ほど|ご回答|お答え/u.test(s) || /(?:でしょうか|ですか|ますか|？|\?)[。]?$/u.test(prev);
      const conditionClause = s.split(/ようでしたら|ようであれば|でしたら|であれば|の場合は|のであれば/u)[0];
      const isPrecondition = PRECONDITION.test(conditionClause);
      if (refersToQuestion && !isPrecondition) push(1, "chained-request", line, "request chained on the other party's reply; ask now, unconditionally");
    }
  }

  // Rhythm: identical endings three in a row inside a paragraph, and sentence-length uniformity.
  for (const p of paragraphs) {
    let run = 1;
    for (let i = 1; i < p.length; i += 1) {
      const a = sentenceEnding(p[i - 1].s);
      const b = sentenceEnding(p[i].s);
      run = a && b && a === b ? run + 1 : 1;
      if (run === 3) push(2, "uniform-endings", p[i].line, `same ending 「${b}」 three sentences in a row`);
    }
  }
  const lengths = paragraphs.flat().map(({ s }) => s.length).filter((n) => n >= 8);
  if (lengths.length >= 8) {
    const mean = lengths.reduce((a, b) => a + b, 0) / lengths.length;
    const sd = Math.sqrt(lengths.reduce((a, b) => a + (b - mean) ** 2, 0) / lengths.length);
    const cv = mean === 0 ? 0 : sd / mean;
    if (cv < 0.35) push(2, "uniform-length", 1, `sentence length coefficient of variation ${cv.toFixed(2)} (< 0.35)`);
  }
  const triads = (whole.match(TRIAD) ?? []).length;
  if (triads >= 2) push(2, "triad", 1, `"three" used ${triads} times as a structuring device`);

  findings.sort((a, b) => a.tier - b.tier || a.line - b.line);
  return findings;
}

export function summarize(findings) {
  const count = (t) => findings.filter((f) => f.tier === t).length;
  return { tier1: count(1), tier2: count(2), tier3: count(3) };
}

function formatFinding(f) {
  const q = f.question ? `\t${f.question}` : "";
  return `TIER${f.tier}\t${f.id}\t${f.source}:${f.line}\t${f.message}${q}`;
}

async function readStdin() {
  let data = "";
  for await (const chunk of process.stdin) data += chunk;
  return data;
}

async function main() {
  const args = process.argv.slice(2);
  const json = args.includes("--json");
  const warn = args.includes("--warn");
  const modeIndex = args.indexOf("--mode");
  const mode = modeIndex >= 0 ? args[modeIndex + 1] : "argument";
  const langIndex = args.indexOf("--lang");
  const lang = langIndex >= 0 ? args[langIndex + 1] : "ja";
  if (!["article", "mail", "argument", "narrative"].includes(mode)) {
    process.stderr.write("JA_HUMANIZER_CHECK_USAGE\t--mode must be article|mail|argument|narrative\n");
    process.exit(2);
  }
  const skip = new Set([modeIndex >= 0 ? modeIndex + 1 : -1, langIndex >= 0 ? langIndex + 1 : -1]);
  const files = args.filter((a, i) => !a.startsWith("--") && !skip.has(i));
  const findings = [];
  if (files.length === 0) {
    findings.push(...lintText(await readStdin(), { source: "stdin", mode, lang }));
  } else {
    for (const file of files) {
      findings.push(...lintText(await readFile(file, "utf8"), { source: file, mode, lang }));
    }
  }
  const s = summarize(findings);
  const status = s.tier1 > 0 && !warn ? "FAIL" : "PASS";
  if (json) {
    process.stdout.write(`${JSON.stringify({ status, summary: s, findings }, null, 2)}\n`);
  } else {
    for (const f of findings) process.stdout.write(`${formatFinding(f)}\n`);
    process.stdout.write(`JA_HUMANIZER_CHECK_SUMMARY\t${status}\ttier1=${s.tier1}\ttier2=${s.tier2}\ttier3=${s.tier3}\n`);
  }
  process.exitCode = status === "FAIL" ? 1 : 0;
}

// Compare real paths: ~/.claude/skills/<name> is usually a symlink into ~/.agents/skills, and
// import.meta.url already resolves to the real file.
const isMain = process.argv[1] && pathToFileURL(realpathSync(process.argv[1])).href === import.meta.url;
if (isMain) await main();
