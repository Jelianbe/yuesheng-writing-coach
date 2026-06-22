// 验证：6 个 SKILL 文件合并内容 vs v5.md 原文
const fs = require('fs');

const v5Content = fs.readFileSync('resources/prompts/yuesheng-prompt-v5.md', 'utf-8');

// 提取 v5.md 中的所有 ## 章节内容（合并为一个字符串用于对比）
// 章节按出现顺序：§一, §二(2.6), §三, §四, §五, §六, §九, §十, §八, §七, §十一
// 但 task 拆分顺序是：core-identity (§一+§二+§2.6), teaching-strategy (§三+§四+§五+§六),
//                      reference-drawer (§九+§十), validation-rules (§八), feedback-cognition (§七), scenario-rules (§十一)
//
// 直接对比每个 SKILL 文件的"内容部分"（去除 frontmatter 和新 wrapper）与 v5.md 相应行段

const slices = [
  { file: 'core-identity.md', start: 20, end: 83 },       // line 21-84
  { file: 'teaching-strategy.md', start: 93, end: 262 },  // line 94-263
  { file: 'reference-drawer.md', start: 265, end: 308 },  // line 266-309
  { file: 'validation-rules.md', start: 318, end: 378 },  // line 319-379
  { file: 'feedback-cognition.md', start: 388, end: 444 },// line 389-445
  { file: 'scenario-rules.md', start: 454, end: 509 },    // line 455-510
];

const v5Lines = v5Content.split(/\r?\n/);

console.log('=== 逐文件内容对比 ===\n');
let totalV5Bytes = 0;
let totalFileBytes = 0;
let allMatch = true;

for (const s of slices) {
  const v5Slice = v5Lines.slice(s.start, s.end + 1).join('\n');
  const v5Bytes = Buffer.byteLength(v5Slice, 'utf-8');

  // 读取 SKILL 文件，去除 frontmatter 和 # SKILL 标题 + 来源/loadWhen blockquote
  const fileContent = fs.readFileSync('resources/prompts/skills/' + s.file, 'utf-8');
  // 找到第一个 '## ' 或 '> 以下为' (scenario-rules) 作为内容开始
  let contentStart = -1;
  const lines = fileContent.split('\n');
  for (let i = 0; i < lines.length; i++) {
    if (/^##\s/.test(lines[i]) || (/^>\s*以下为/.test(lines[i]))) {
      contentStart = i;
      break;
    }
  }
  if (contentStart < 0) {
    console.log(s.file + ': ERROR - 找不到内容起始');
    allMatch = false;
    continue;
  }
  const fileContentSlice = lines.slice(contentStart).join('\n');
  const fileBytes = Buffer.byteLength(fileContentSlice, 'utf-8');

  // 简单对比
  const match = v5Slice === fileContentSlice;
  if (!match) {
    allMatch = false;
    console.log(s.file + ': MISMATCH');
    console.log('  v5 slice bytes:', v5Bytes);
    console.log('  file slice bytes:', fileBytes);
    // 找出第一个差异
    let i = 0;
    const min = Math.min(v5Slice.length, fileContentSlice.length);
    while (i < min && v5Slice[i] === fileContentSlice[i]) i++;
    console.log('  first diff at char:', i);
    console.log('  v5 around:', JSON.stringify(v5Slice.substring(Math.max(0, i - 20), i + 20)));
    console.log('  file around:', JSON.stringify(fileContentSlice.substring(Math.max(0, i - 20), i + 20)));
  } else {
    console.log(s.file + ': OK (' + v5Bytes + ' bytes)');
  }
  totalV5Bytes += v5Bytes;
  totalFileBytes += fileBytes;
}

console.log('\n=== 汇总 ===');
console.log('v5.md 各段内容总字节:', totalV5Bytes);
console.log('6 文件对应内容总字节:', totalFileBytes);
console.log('v5.md 全文字节:', Buffer.byteLength(v5Content, 'utf-8'));
console.log('v5.md 头部+wrapper 总字节:', Buffer.byteLength(v5Content, 'utf-8') - totalV5Bytes);
console.log('总匹配:', allMatch ? 'YES' : 'NO');

// 也计算 wc -c 风格行数
console.log('\n=== 行数对比 ===');
console.log('v5.md:', v5Lines.length, 'lines');
for (const s of slices) {
  const f = fs.readFileSync('resources/prompts/skills/' + s.file, 'utf-8');
  console.log(s.file + ':', f.split('\n').length, 'lines');
}
