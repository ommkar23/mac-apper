import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { deflateSync } from 'node:zlib';
function png() {
  const chunk = (name,data) => {
    const body=Buffer.concat([Buffer.from(name),data]);
    let crc=0xffffffff;
    for(const byte of body){crc^=byte;for(let bit=0;bit<8;bit++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}
    const head=Buffer.alloc(4),tail=Buffer.alloc(4);
    head.writeUInt32BE(data.length);tail.writeUInt32BE((crc^0xffffffff)>>>0);
    return Buffer.concat([head,body,tail]);
  };
  const header=Buffer.alloc(13);header.writeUInt32BE(1,0);header.writeUInt32BE(1,4);header[8]=8;header[9]=6;
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(Buffer.from([0,255,0,0,255]))),chunk('IEND',Buffer.alloc(0))]);
}

// Only this installed filesystem module is loaded. No Pi session, authentication or network.
test('real harness production read preserves absolute archive bytes after project deletion', async () => {
  const tmp = process.env.TMPDIR;
  assert.ok(tmp?.includes('/mac-apper/.tmp/'));
  const info = await fs.lstat(tmp); assert.ok(info.isDirectory() && !info.isSymbolicLink());
  assert.equal(info.mode & 0o077,0);
  const module = process.env.DEV_TOOLS_SCENARIO_PI_READ_MODULE;
  assert.ok(module?.startsWith('/')); assert.ok((await fs.lstat(module)).isFile());
  const home = await fs.mkdtemp(path.join(tmp,'preview-offline-read-'));
  await fs.chmod(home,0o700);
  let passed = false;
  try {
    const project = path.join(home,'.mac-apper','project');
    const archive = path.join(home,'.mac-apper','previews','project','session');
    await fs.mkdir(project,{recursive:true,mode:0o700}); await fs.mkdir(archive,{recursive:true,mode:0o700});
    const file = path.join(await fs.realpath(archive),'preview-1.png');
    const bytes = png();
    await fs.writeFile(file,bytes,{mode:0o600});
    await fs.rm(project,{recursive:true});
    const harness = fileURLToPath(new URL('./PreviewToolHarness.ts',import.meta.url));
    const child = spawn(process.execPath,['--no-warnings','--experimental-strip-types',harness], {
      shell:false,stdio:['pipe','pipe','pipe'],env:{HOME:home,CFFIXED_USER_HOME:home,TMPDIR:tmp,
        OPENXPC_PROJECT_ROOT:project,OPENXPC_PROJECT_ID:'project',OPENXPC_SESSION_ID:'session',DEV_TOOLS_SCENARIO_PI_READ_MODULE:module}
    });
    let stdout='',stderr='';
    child.stdout.on('data',chunk=>{stdout+=chunk;assert.ok(Buffer.byteLength(stdout)<=131072);});
    child.stderr.on('data',chunk=>{stderr+=chunk;});
    child.stdin.end(JSON.stringify({readPath:file})+'\n');
    const code = await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',resolve);});
    assert.equal(code,0,stderr); assert.equal(stderr,'');
    const envelope=JSON.parse(stdout);
    const image=envelope.result.content.find(block=>block.type==='image');
    assert.ok(image); assert.equal(image.mimeType,'image/png');
    assert.deepEqual(Buffer.from(image.data,'base64'),bytes);
    assert.deepEqual(await fs.readFile(file),bytes);
    await assert.rejects(fs.stat(project));
    passed=true;
  } finally {
    if(passed) await fs.rm(home,{recursive:true});
    else console.error(`OFFLINE_PREVIEW_FIXTURE_RETAINED ${home}`);
  }
});
