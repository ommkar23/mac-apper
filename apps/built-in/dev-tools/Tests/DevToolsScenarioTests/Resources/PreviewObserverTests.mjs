import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyObservation, observeSpawn } from './PreviewToolHarness.ts';
import childProcess from 'node:child_process';
const ids = { requestID: 'a', projectID: 'b', sessionID: 'c' };
const request = JSON.stringify({ version: 1, ...ids, command: 'preview', payload: Buffer.from('{}').toString('base64') }) + '\n';
const response = (fields) => JSON.stringify({ version: 1, requestID: 'a', projectID: 'b', ...fields }) + '\n';
const bound = { executable: '/client', projectID: 'b', sessionID: 'c', projectRoot: '/project', environment: {HOME:'/home', CFFIXED_USER_HOME:'/home', TMPDIR:'/repo/.tmp/'} };
const sample = (fields = {}) => ({ executable:'/client', args:[], options:{shell:false,stdio:['pipe','pipe','pipe'],env:{...bound.environment,OPENXPC_PROJECT_ID:'b',OPENXPC_SESSION_ID:'c'}}, stdin:request.replace('e30=', Buffer.from('{"projectRoot":"/project"}').toString('base64')), stdout:response({success:false,error:'operationFailed'}), stderr:'', closed:true, code:1, signal:null, fault:false, ...fields });
test('identified operationFailed is correlated; only controlled expected rejection may confirm it', () => {
  assert.equal(classifyObservation([sample()], bound), 'operationFailed');
  for (const fields of [{executable:'/other'},{args:['--other']},{options:{shell:true}},{closed:false},{code:0},{stderr:'error'},{stdout:response({success:false,error:'invalidResponse'})},{stdout:response({success:false,error:'cleanupFailed'})},{stdout:response({success:true,payload:Buffer.from('{"status":"error","summary":"cleanupFailed"}').toString('base64')})},{stdin:request},{fault:true},{stdout:response({success:false,error:'operationFailed',requestID:'other'})},{stdout:response({success:false,error:'operationFailed'})+'\n'}]) assert.throws(() => classifyObservation([sample(fields)], bound));
  for(const options of [
    {...sample().options,env:{...sample().options.env,SECRET:'forbidden'}},
    {...sample().options,env:{...sample().options.env,OPENXPC_SESSION_ID:'other'}},
    {...sample().options,stdio:['inherit','pipe','pipe']}
  ]) assert.throws(() => classifyObservation([sample({options})],bound));
  assert.throws(() => classifyObservation([], bound));
  assert.throws(() => classifyObservation([sample(),sample()], bound));
});
test('typed ordinary errors and rendered payloads preserve completion', () => {
  for(const status of ['error','rendered']) assert.equal(classifyObservation([sample({code:0,stdout:response({success:true,payload:Buffer.from(JSON.stringify({status,summary:'processFailed'})).toString('base64')})})],bound),'completed');
});
test('observer forwards exact real spawn arguments and waits for actual close', async () => {
  const records=[];
  const options={shell:false,stdio:['pipe','pipe','pipe'],env:{TMPDIR:process.env.TMPDIR}};
  let seen;
  const real=(...args)=>{seen=args;return childProcess.spawn(...args);};
  const args=['-e','process.stdin.pipe(process.stdout)'];
  const child=observeSpawn(real,records)(process.execPath,args,options);
  assert.equal(seen[1],args); assert.equal(seen[2],options);
  child.stdin.end('real bounded bytes\n');
  await records[0].done;
  assert.equal(records[0].closed,true); assert.equal(records[0].stdout,'real bounded bytes\n');
  assert.equal(records[0].stdin,'real bounded bytes\n'); assert.equal(records[0].code,0);
});
test('overflow observation remains bounded without changing real forwarded traffic', async () => {
  const records=[];
  const child=observeSpawn(childProcess.spawn,records)(process.execPath,
    ['-e','let n=0;process.stdin.on("data",b=>n+=b.length);process.stdin.on("end",()=>process.stdout.write(String(n)))'],
    {shell:false,stdio:['pipe','pipe','pipe'],env:{TMPDIR:process.env.TMPDIR}});
  const input=Buffer.alloc(131073,97);
  child.stdin.end(input);
  await records[0].done;
  assert.equal(records[0].stdout,String(input.length));
  assert.equal(records[0].fault,true);
  assert.ok(Buffer.byteLength(records[0].stdin)<=131072);
});
