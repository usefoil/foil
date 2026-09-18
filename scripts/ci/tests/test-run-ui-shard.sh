#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
test -f "$repo_root/scripts/ci/run-ui-shard.sh"
node --input-type=module - "$repo_root" <<'JS'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { pathToFileURL } from 'node:url'
const source = process.argv[2]
const {aggregateReceipts}=await import(pathToFileURL(path.join(source,'scripts','ci','aggregate-ui-gate.mjs')));
const successfulReceipts=[];
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'foil-shard-contract-'))
const fake = String.raw`
const fs = require('fs'), path = require('path');
const [kind, ...args] = process.argv.slice(2), env = process.env;
const scenario = env.SCENARIO, calls = env.CALLS;
const value = name => args[args.indexOf(name) + 1];
fs.appendFileSync(calls, JSON.stringify({kind,args,live:[env.RUN_LIVE_GROQ_TESTS,env.RUN_LIVE_MICROPHONE_TESTS],
  reuse:env.SKIP_BUILD_FOR_TESTING,xctestrun:env.XCTESTRUN_PATH,result:env.XCTEST_RESULT_BUNDLE_PATH,fixtureArtifacts:env.XCTEST_ARTIFACT_DIR})+'\n');
if (kind === 'git') { console.log(scenario === 'wrong-sha' ? 'wrong' : 'abc123'); process.exit(0); }
if (kind === 'preflight') {
  if(scenario==='malformed-preflight'){fs.writeFileSync(value('--output'),'{}');process.exit(0);}
  const baseline=JSON.parse(fs.readFileSync(value('--baseline'))),runnerName=baseline.allowedRunnerNames[{a:0,b:1,c:2}[env.FOIL_CI_SHARD]];
  const facts={hostname:'fake.local',architecture:baseline.architecture,productVersion:baseline.productVersion,buildVersion:baseline.buildVersion,
    xcodeVersion:baseline.xcodeVersion,xcodeBuild:baseline.xcodeBuild,freeBytes:baseline.minimumFreeBytes+1,runnerName,
    consoleUser:baseline.allowedConsoleUsers[0],screenLocked:false,developerModeEnabled:true,runnerOs:'macOS',runnerArch:'ARM64',
    activeRunnerServices:['actions.runner.usefoil-foil.'+runnerName]};
  fs.writeFileSync(value('--output'), JSON.stringify({schemaVersion:1,status:scenario==='drift'?'drift':'healthy',facts,errors:scenario==='drift'?['drift']:[]}));
  process.exit(scenario==='drift'?2:0);
}
if (kind === 'cleanup') {
  if (value('--mode') === 'after') {
    assertReceipt();
    if(scenario==='hung-finalization-cleanup'){
      process.on('SIGTERM',()=>{});setTimeout(()=>process.exit(1),12000);return;
    }
    if(scenario==='retry-expired'){
      const receipt=JSON.parse(fs.readFileSync(path.join(process.cwd(),'artifacts','receipt-'+env.FOIL_CI_SHARD+'.json')));
      if(receipt.retryAllowed!==true)throw Error('retry must be eligible before cleanup consumes its budget');
      setTimeout(()=>{fs.rmSync(value('--run-root'),{recursive:true,force:true});process.exit(0)},6000);return;
    }
    if (scenario==='cleanup-failure') process.exit(1);
    fs.rmSync(value('--run-root'), {recursive:true,force:true});
  }
  process.exit(0);
}
function assertReceipt() {
  if (!fs.existsSync(path.join(process.cwd(),'artifacts','receipt-'+env.FOIL_CI_SHARD+'.json'))) throw Error('cleanup before receipt preservation');
}
if (kind === 'fixture') {
  if (env.SKIP_BUILD_FOR_TESTING!=='1' || !fs.existsSync(env.XCTESTRUN_PATH)) throw Error('fixture rebuilt or missing xctestrun');
  fs.mkdirSync(env.XCTEST_RESULT_BUNDLE_PATH,{recursive:true});
  process.exit(scenario==='fixture-failure'?65:0);
}
if (kind === 'xcodebuild') {
  if (args[0] === 'build-for-testing') {
    fs.mkdirSync(value('-resultBundlePath'),{recursive:true});
    const builds=fs.readFileSync(calls,'utf8').trim().split('\n').map(JSON.parse).filter(c=>c.kind==='xcodebuild'&&c.args[0]==='build-for-testing').length;
    if (scenario==='build-always-fails' || (scenario==='build-retry'&&builds===1) || scenario==='short-budget'||scenario==='retry-expired') process.exit(65);
    const products=path.join(value('-derivedDataPath'),'Build','Products');fs.mkdirSync(products,{recursive:true});fs.writeFileSync(path.join(products,'Foil.xctestrun'),'fake');
    if(scenario==='multiple-xctestruns')fs.writeFileSync(path.join(products,'Other.xctestrun'),'fake');
  } else if (args.includes('-enumerate-tests')) {
    console.error('Failed to initialize for UI testing: Timed out while enabling automation mode.');
    process.exit(65);
  } else {
    fs.mkdirSync(value('-resultBundlePath'),{recursive:true});
    if(scenario==='signal'){process.kill(process.ppid,'SIGTERM');process.exit(65);}
    if(scenario==='signal-stubborn'){
      process.on('SIGTERM',()=>{});process.kill(process.ppid,'SIGTERM');setTimeout(()=>process.exit(65),6000);return;
    }
    if(scenario==='assertion')process.exit(65);
  }
  process.exit(0);
}
if(kind==='xcrun') {
  const fixture=value('--path').includes('fixture'), name=fixture?'testE2ETranscription':({a:'testAlpha',b:'testBeta',c:'testGamma'})[env.FOIL_CI_SHARD];
  if(scenario==='malformed'){console.log('{}');process.exit(0);}
  if(args[3]==='tests'&&['hung-report','failed-hung-tree'].includes(scenario)){
    process.on('SIGTERM',()=>{});setTimeout(()=>process.exit(1),6000);return;
  }
  if(args[3]==='tests'&&scenario==='failed-malformed-tree'){console.log('{}');process.exit(0);}
  if(args[3]==='tests'&&scenario==='failed-missing-tree')process.exit(1);
  let result=scenario==='assertion'||scenario.startsWith('failed-')||(fixture&&scenario==='fixture-failure')?'Failed':scenario==='skip'?'Skipped':'Passed';
  const nodes=scenario==='missing-result'?[]:[{nodeType:'Test Case',name:name+'()',nodeIdentifier:'FoilUITests/'+(scenario==='wrong-test'?'testOther':name)+'()',result}];
  if(args[3]==='summary')console.log(JSON.stringify({title:'Tests',environmentDescription:'Mac',topInsights:[],result,
    totalTestCount:nodes.length,passedTests:result==='Passed'?nodes.length:0,failedTests:result==='Failed'?nodes.length:0,skippedTests:result==='Skipped'?nodes.length:0,
    expectedFailures:0,statistics:[],devicesAndConfigurations:[],testFailures:[]}));
  else if(args[3]==='tests')console.log(JSON.stringify({devices:[],testPlanConfigurations:[],testNodes:[{nodeType:'UI test bundle',name:'FoilUITests',children:nodes}]}));
  else throw Error('unexpected xcresult command');
  process.exit(0);
}
throw Error('unexpected fake command '+kind);
`
const scenarios = [
  ['hung-report','a','infra_failed',1],['failed-hung-tree','a','test_failed',1],
  ['hung-finalization-cleanup','a','infra_failed',1],
  ['success','a','passed',1],['success','b','passed',1],['success','c','passed',1],
  ['assertion','c','test_failed',1],['fixture-failure','c','test_failed',1],['skip','a','test_failed',1],
  ['missing-result','a','test_failed',1],['wrong-test','a','test_failed',1],
  ['malformed','a','infra_failed',1],['build-retry','a','passed',2],['automation-timeout-avoided','a','passed',1],['build-always-fails','a','infra_failed',2],
  ['short-budget','a','infra_failed',1],['drift','a','infra_failed',0],['wrong-sha','a','infra_failed',0],
  ['source-inventory-drift','a','infra_failed',0],['multiple-xctestruns','a','infra_failed',1],
  ['cleanup-failure','a','infra_failed',1],['signal','a','infra_failed',1],['malformed-preflight','a','infra_failed',0],
  ['signal-stubborn','a','infra_failed',1],['retry-expired','a','infra_failed',1],
  ['failed-malformed-tree','a','test_failed',1],['failed-missing-tree','a','test_failed',1],
  ['invalid-selectors','a','infra_failed',0]
]
try {
  for (const [scenario,shard,classification,buildCount] of scenarios) {
    const root=path.join(temp,scenario+'-'+shard), ci=path.join(root,'scripts','ci'), bin=path.join(root,'bin'), workspace=path.join(root,'workspace');
    fs.mkdirSync(ci,{recursive:true});fs.mkdirSync(bin);fs.mkdirSync(workspace);
    for(const name of ['run-ui-shard.sh','shard-receipt.mjs','ui-test-inventory.mjs','runner-baseline.json'])fs.copyFileSync(path.join(source,'scripts','ci',name),path.join(ci,name));
    fs.writeFileSync(path.join(ci,'ui-test-shards.json'),JSON.stringify({suite:'FoilUITests/FoilUITests',shards:{a:[scenario==='invalid-selectors'?'testAlpha/*':'testAlpha'],b:['testBeta'],c:['testGamma']},specialTests:{testE2ETranscription:{shard:'c'}},excluded:{testLiveMicrophoneSmoke:{}}}));
    const uiSource=path.join(root,'FoilUITests','FoilUITests.swift');fs.mkdirSync(path.dirname(uiSource),{recursive:true});
    const sourceTests=scenario==='source-inventory-drift'?['testAlpha','testBeta','testE2ETranscription','testLiveMicrophoneSmoke']:['testAlpha','testBeta','testGamma','testE2ETranscription','testLiveMicrophoneSmoke'];
    fs.writeFileSync(uiSource,sourceTests.map(name=>'func '+name+'() {}').join('\n'));
    fs.writeFileSync(path.join(root,'fake.cjs'),fake);
    for(const name of ['git','xcodebuild','xcrun'])fs.writeFileSync(path.join(bin,name),'#!/usr/bin/env bash\nexec node "'+path.join(root,'fake.cjs')+'" '+name+' "$@"\n',{mode:0o755});
    fs.writeFileSync(path.join(ci,'runner-preflight.mjs'),`import {spawnSync} from 'node:child_process';process.exit(spawnSync('node',[${JSON.stringify(path.join(root,'fake.cjs'))},'preflight',...process.argv.slice(2)],{stdio:'inherit'}).status);`);
    for(const [file,kind] of [['ci/runner-cleanup.sh','cleanup'],['run-fixture-transcription-e2e-xcuitest.sh','fixture']])fs.writeFileSync(path.join(root,'scripts',file),'#!/usr/bin/env bash\nexec node "'+path.join(root,'fake.cjs')+'" '+kind+' "$@"\n',{mode:0o755});
    const calls=path.join(root,'calls.jsonl');
    const started=Date.now();
    const run=spawnSync('/bin/bash',[path.join(ci,'run-ui-shard.sh')],{cwd:root,encoding:'utf8',timeout:15000,
      env:{...process.env,PATH:bin+':'+process.env.PATH,SCENARIO:scenario,CALLS:calls,FOIL_CI_SHARD:shard,GITHUB_RUN_ID:'123',GITHUB_RUN_ATTEMPT:'9',GITHUB_SHA:'abc123',RUNNER_WORKSPACE:workspace,
        RUN_LIVE_GROQ_TESTS:'1',RUN_LIVE_MICROPHONE_TESTS:'1',
        FOIL_CI_SHARD_TIMEOUT_SECONDS:scenario==='short-budget'?'179':scenario==='retry-expired'?'185':scenario.includes('hung')?'2':'840'}});
    assert.equal(run.error,undefined,scenario+': '+run.error);
    if(['hung-report','failed-hung-tree'].includes(scenario))assert.ok(Date.now()-started<5000,'deadline must interrupt a stubborn report collector before finalization');
    if(scenario==='hung-finalization-cleanup')assert.ok(Date.now()-started<11000,'finalization must bound an uncooperative cleanup command');
    if(scenario==='signal-stubborn')assert.ok(Date.now()-started<5000,'signal cleanup must not wait indefinitely for an uncooperative child');
    const receipt=JSON.parse(fs.readFileSync(path.join(root,'artifacts','receipt-'+shard+'.json')));
    assert.equal(receipt.classification,classification,scenario+': '+JSON.stringify(receipt)+'\n'+run.stderr);
    assert.equal(run.status===0,classification==='passed',scenario+': exit '+run.status+'\n'+run.stderr);
    assert.equal(receipt.workflowAttempt,'9');
    const expectedTests=shard==='c'?['FoilUITests/FoilUITests/testE2ETranscription','FoilUITests/FoilUITests/testGamma']:
      ['FoilUITests/FoilUITests/'+(shard==='a'?'testAlpha':'testBeta')];
    assert.deepEqual(receipt.expectedTests,scenario==='invalid-selectors'?[]:expectedTests,scenario+' normalized expectation schema');
    if(scenario==='success')successfulReceipts.push(receipt);
    if(scenario==='invalid-selectors'){
      assert.equal(receipt.invalidSelectors,true);assert.equal(receipt.retryAllowed,false);
    }
    if(['hung-report','failed-hung-tree'].includes(scenario)){
      assert.equal(receipt.interrupted,true);assert.equal(receipt.retryAllowed,false);
      assert.equal(receipt.testsStarted,1,'retain the summary collected before the timeout');
    }
    if(scenario.startsWith('failed-')){
      assert.equal(receipt.retryAllowed,false);
      assert.equal(receipt.testsStarted,1);
      assert.ok(receipt.diagnostics.some(message=>message.includes('exact failed test names could not be recovered')));
    }
    const events=fs.readFileSync(calls,'utf8').trim().split('\n').map(JSON.parse);
    const builds=events.filter(e=>e.kind==='xcodebuild'&&e.args[0]==='build-for-testing');
    assert.equal(builds.length,buildCount,scenario);
    for(const e of events)assert.deepEqual(e.live,['0','0'],scenario+' live flags');
    const tests=events.filter(e=>e.kind==='xcodebuild'&&e.args[0]==='test-without-building'&&!e.args.includes('-enumerate-tests'));
    assert.equal(events.filter(e=>e.kind==='xcodebuild'&&e.args.includes('-enumerate-tests')).length,0,scenario+' must not launch UI automation during inventory validation');
    for(const e of tests)assert.deepEqual(e.args.filter(a=>a.startsWith('-only-testing:')),['-only-testing:FoilUITests/FoilUITests/'+({a:'testAlpha',b:'testBeta',c:'testGamma'})[shard]],scenario);
    const fixture=events.filter(e=>e.kind==='fixture');
    assert.equal(fixture.length,shard==='c'&&scenario!=='assertion'?1:0,scenario);
    if(fixture.length){
      assert.equal(fixture[0].reuse,'1');assert.equal(fixture[0].xctestrun,tests[0].args[tests[0].args.indexOf('-xctestrun')+1]);
      assert.ok(fixture[0].fixtureArtifacts?.endsWith('/attempt-1/fixture-artifacts'));
    }
    assert.ok(events.some(e=>e.kind==='cleanup'&&e.args.includes('after')),scenario+' after cleanup');
    if(buildCount===2){
      assert.equal(receipt.localAttempt,2);
      const first=JSON.parse(fs.readFileSync(path.join(root,'artifacts','shard-'+shard,'attempt-1','receipt.json')));
      assert.equal(first.classification,'infra_failed');assert.equal(first.retryAllowed,true);
      assert.deepEqual(first.expectedTests,expectedTests,'provisional receipt preserves normalized expectations');
      assert.ok(fs.existsSync(path.join(root,'artifacts','shard-'+shard,'attempt-1','build.log')));
    }
    if(!['cleanup-failure','hung-finalization-cleanup'].includes(scenario))assert.equal(fs.existsSync(path.join(workspace,'foil-ci-runs','123-9-'+shard)),false,scenario+' build state removed');
    console.log('PASS '+scenario+' shard '+shard);
  }
  const gate=aggregateReceipts(successfulReceipts,'abc123');
  assert.deepEqual(gate.errors,[],'actual successful executor receipts must satisfy the strict aggregate consumer');
  assert.equal(gate.status,'passed');
  console.log('PASS strict aggregate consumes all three successful receipts');
} finally {fs.rmSync(temp,{recursive:true,force:true})}
JS
