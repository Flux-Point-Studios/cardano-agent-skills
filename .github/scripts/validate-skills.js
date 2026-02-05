#!/usr/bin/env node

/**
 * Validates all SKILL.md files in the skills/ directory
 * Checks:
 * - Valid YAML frontmatter
 * - Required fields (name, description)
 * - Name constraints (lowercase, hyphens, max 64 chars, no reserved words)
 * - No duplicate names
 */

const fs = require('fs');
const path = require('path');
const yaml = require('yaml');

const RESERVED_WORDS = ['claude', 'anthropic', 'skill', 'openai', 'gpt'];
const MAX_NAME_LENGTH = 64;
const NAME_PATTERN = /^[a-z][a-z0-9-]*$/;

const skillsDir = path.join(__dirname, '..', '..', 'skills');
const errors = [];
const warnings = [];
const seenNames = new Set();

function extractFrontmatter(content) {
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return null;
  try {
    return yaml.parse(match[1]);
  } catch (e) {
    return { _parseError: e.message };
  }
}

function validateSkill(skillPath, skillName) {
  const skillMdPath = path.join(skillPath, 'SKILL.md');

  if (!fs.existsSync(skillMdPath)) {
    errors.push(`${skillName}: Missing SKILL.md file`);
    return;
  }

  const content = fs.readFileSync(skillMdPath, 'utf8');
  const frontmatter = extractFrontmatter(content);

  if (!frontmatter) {
    errors.push(`${skillName}: No YAML frontmatter found`);
    return;
  }

  if (frontmatter._parseError) {
    errors.push(`${skillName}: Invalid YAML frontmatter - ${frontmatter._parseError}`);
    return;
  }

  // Required fields
  if (!frontmatter.name) {
    errors.push(`${skillName}: Missing required field 'name'`);
  }
  if (!frontmatter.description) {
    errors.push(`${skillName}: Missing required field 'description'`);
  }

  const name = frontmatter.name;
  if (name) {
    // Name validation
    if (!NAME_PATTERN.test(name)) {
      errors.push(`${skillName}: Name '${name}' must be lowercase with hyphens only, starting with a letter`);
    }
    if (name.length > MAX_NAME_LENGTH) {
      errors.push(`${skillName}: Name '${name}' exceeds ${MAX_NAME_LENGTH} characters`);
    }
    for (const reserved of RESERVED_WORDS) {
      if (name.includes(reserved)) {
        errors.push(`${skillName}: Name '${name}' contains reserved word '${reserved}'`);
      }
    }
    if (seenNames.has(name)) {
      errors.push(`${skillName}: Duplicate skill name '${name}'`);
    }
    seenNames.add(name);

    // Name should match directory
    if (name !== skillName) {
      warnings.push(`${skillName}: Skill name '${name}' doesn't match directory name '${skillName}'`);
    }
  }

  // Description length check
  if (frontmatter.description && frontmatter.description.length > 200) {
    warnings.push(`${skillName}: Description is long (${frontmatter.description.length} chars). Consider shortening for token efficiency.`);
  }

  console.log(`✓ ${skillName}`);
}

// Main
console.log('Validating skills...\n');

if (!fs.existsSync(skillsDir)) {
  console.error('Error: skills/ directory not found');
  process.exit(1);
}

const skills = fs.readdirSync(skillsDir).filter(f => {
  return fs.statSync(path.join(skillsDir, f)).isDirectory();
});

for (const skill of skills) {
  validateSkill(path.join(skillsDir, skill), skill);
}

console.log(`\nValidated ${skills.length} skills`);

if (warnings.length > 0) {
  console.log('\nWarnings:');
  warnings.forEach(w => console.log(`  ⚠ ${w}`));
}

if (errors.length > 0) {
  console.log('\nErrors:');
  errors.forEach(e => console.log(`  ✗ ${e}`));
  process.exit(1);
}

console.log('\n✓ All skills valid!');
