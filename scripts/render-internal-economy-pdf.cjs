// Render the exact application export with a previously fetched Hub report.
const fs=require('node:fs'),path=require('node:path'),Module=require('node:module'),ts=require('typescript');
const modules=new Map();
function load(file){file=path.resolve(file);if(modules.has(file))return modules.get(file);const m=new Module(file,module);m.filename=file;m.paths=module.paths;m.require=name=>name.startsWith('.')?load(path.resolve(path.dirname(file),name+'.ts')):require(name);const source=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS}}).outputText;m._compile(source,file);modules.set(file,m.exports);return m.exports;}
const[reportPath,outputPath,center]=process.argv.slice(2);
if(!reportPath||!outputPath)throw Error('Usage: node scripts/render-internal-economy-pdf.cjs report.json output.pdf [20|30]');
load('src/lib/kpi/internal-economy-pdf.ts').internalEconomyPdf(JSON.parse(fs.readFileSync(reportPath,'utf8')),center).then(bytes=>{fs.writeFileSync(outputPath,bytes);console.log(outputPath);}).catch(error=>{console.error(error);process.exitCode=1;});
