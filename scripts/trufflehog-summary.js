// Turns TruffleHog --json output into a redacted report and a log summary.
// Usage: node scripts/trufflehog-summary.js <raw.json> <redacted-report.json>
// The secret values (Raw, RawV2, Redacted, ExtraData) are never printed or kept.
const fs = require('node:fs');

const [input, output] = process.argv.slice(2);
const lines = fs.existsSync(input) ? fs.readFileSync(input, 'utf8').split('\n') : [];

const findings = [];
for (const line of lines) {
  if (!line.trim().startsWith('{')) continue;
  let result;
  try {
    result = JSON.parse(line);
  } catch {
    continue;
  }
  if (!result.DetectorName) continue;
  const git = (result.SourceMetadata && result.SourceMetadata.Data && result.SourceMetadata.Data.Git) || {};
  findings.push({
    detector: result.DetectorName,
    verified: Boolean(result.Verified),
    commit: git.commit,
    file: git.file,
    line: git.line,
    timestamp: git.timestamp
  });
}

fs.writeFileSync(output, JSON.stringify(findings, null, 2) + '\n');

const verified = findings.filter(f => f.verified).length;
console.log(`TruffleHog: ${findings.length} finding(s), ${verified} verified`);
for (const f of findings) {
  const commit = f.commit ? f.commit.slice(0, 10) : '-';
  console.log(`  [${f.verified ? 'VERIFIED' : 'unverified'}] ${f.detector}  ${f.file}:${f.line}  commit ${commit}`);
}
