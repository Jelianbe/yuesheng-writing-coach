const path = require('path');
const fs = require('fs');

// Possible DB locations
const candidates = [
  path.join(process.env.APPDATA || '', 'yuesheng-writing-coach'),
  path.join(process.cwd(), 'data'),
  path.join(process.cwd(), 'dist', 'data'),
  path.join(process.cwd()),
];

console.log('=== Searching for yuesheng.db ===');
for (const dir of candidates) {
  const p = path.join(dir, 'yuesheng.db');
  if (fs.existsSync(p)) {
    console.log('FOUND:', p, `(${fs.statSync(p).size} bytes)`);
    // Try to read it - better-sqlite3 is native, fall back to using sqlite3 CLI
    try {
      const Database = require('better-sqlite3');
      const db = new Database(p);
      const chapters = db.prepare('SELECT id, title, length(content) as content_len FROM chapters').all();
      console.log('Chapters:', JSON.stringify(chapters, null, 2));
      if (chapters.length > 0) {
        chapters.forEach(c => {
          console.log(`  ${c.id}: "${c.title}" (${c.content_len} chars)`);
        });
      }
      db.close();
    } catch (e) {
      console.log('  (need sqlite3 CLI to read)');
    }
  } else {
    console.log('NOT FOUND:', p);
  }
}
