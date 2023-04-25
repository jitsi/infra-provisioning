const fs = require('fs');
const process = require('process');

function aggregate(template, j) {
    Object.getOwnPropertyNames(template).forEach(field => {
        if (Array.isArray(template[field])) {
            if (!Array.isArray(j[field]) || j[field].length !== template[field].length) {
                process.stderr.write(`Error summing array ${field}\n`);
                return;
            }
            for (let i = 0; i < j[field].length; i++) {
                template[field][i] = template[field][i] + j[field][i];
            }
        } else if (typeof template[field] === 'number' && typeof j[field] === 'number') {
            template[field] = template[field] + j[field];
        } else if (typeof template[field] === 'object') {
            if (typeof j[field] === 'object') {
                aggregate(template[field], j[field]);
            }
            // silently skip objects that are missing from j
        } else {
            process.stderr.write(`Skipping field ${field}.\n`);
        }
    });
}

if (process.argv.length < 3) {
    process.stderr.write(`Usage: ${process.argv[0]} ${process.argv[1]} <template> <files ...>\n`);
    process.exit(1);
}

process.env.DEBUG && process.stderr.write(`Using template ${process.argv[2]}\n`);
const template = JSON.parse(fs.readFileSync(process.argv[2]));

var count = 0;
process.argv.splice(3).forEach(f => {
  process.env.DEBUG && process.stderr.write(`Adding ${f}\n`);
  try {
      const j = JSON.parse(fs.readFileSync(f));

      aggregate(template, j);
      count++;
  } catch(e) {
      process.stderr.write(`Ignoring ${f} because: ${e}\n`);
  }
});

process.stderr.write(`Aggregated ${count} files.\n`);

console.log(JSON.stringify(template));
