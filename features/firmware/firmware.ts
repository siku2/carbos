// Shows and updates the firmware of the devices in the manifest that the
// carbos.firmware options render.
import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline/promises";

type Method =
  | { fwupd: { instanceId: string; images: string[] } }
  | { samsungNvme: { device: string } }
  | { xmos: { vendorId: string; productId: string; image: string } }
  | { amdGpu: { instanceId: string; partNumber: string; images: string[] } }
  | { esp: { image: string } };

interface Device {
  description: string;
  version: string;
  package: string;
  method: Method;
}

interface Manifest {
  esp: string;
  devices: Record<string, Device>;
}

interface Adapter {
  // Undefined when the device is not connected.
  current(): string | undefined;
  flash(): void;
}

class Failure extends Error {}

function run(
  command: string,
  args: string[],
  env?: Record<string, string>,
): string {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    env: { ...process.env, ...env },
  });
  if (result.status !== 0) {
    throw new Failure(
      `${command} ${args.join(" ")} failed:\n${result.stderr}${result.stdout}`,
    );
  }
  return result.stdout;
}

// With --dry-run, commands that change a device only get printed.
let dryRun = false;

function write(
  command: string,
  args: string[],
  env?: Record<string, string>,
): boolean {
  console.log(`${dryRun ? "would run" : "$"} ${command} ${args.join(" ")}`);
  if (dryRun) return true;
  const result = spawnSync(command, args, {
    stdio: "inherit",
    env: { ...process.env, ...env },
  });
  return result.status === 0;
}

interface FwupdDevice {
  DeviceId: string;
  Version?: string;
  InstanceIds?: string[];
}

function fwupd(
  tool: "fwupdmgr" | "fwupdtool",
  instanceId: string,
): FwupdDevice | undefined {
  const output = JSON.parse(run(tool, ["get-devices", "--json"])) as {
    Devices?: FwupdDevice[];
  };
  return output.Devices?.find((device) =>
    device.InstanceIds?.includes(instanceId),
  );
}

function fwupdAdapter(
  device: Device,
  method: { instanceId: string; images: string[] },
): Adapter {
  return {
    current: () => fwupd("fwupdmgr", method.instanceId)?.Version,
    flash: () =>
      fwupdInstall(
        method.instanceId,
        method.images.map((image) => join(device.package, image)),
      ),
  };
}

function fwupdInstall(
  instanceId: string,
  paths: string[],
  flags: string[] = [],
): void {
  // The daemon would hold the devices while fwupdtool writes.
  write("systemctl", ["stop", "fwupd.service"]);
  try {
    let remaining = paths;
    // An image fwupd rejects, like one for the running slot, gets another try
    // after the others.
    for (let pass = 0; pass < paths.length && remaining.length > 0; pass++) {
      remaining = remaining.filter((path) => {
        const target = fwupd(dryRun ? "fwupdmgr" : "fwupdtool", instanceId);
        if (target === undefined) {
          throw new Failure(`no fwupd device with instance ID ${instanceId}`);
        }
        return !write("fwupdtool", [
          "install-blob",
          path,
          target.DeviceId,
          "--assume-yes",
          "--no-reboot-check",
          ...flags,
        ]);
      });
    }
    if (remaining.length > 0) {
      throw new Failure(`fwupdtool did not install ${remaining.join(", ")}`);
    }
  } finally {
    write("systemctl", ["start", "fwupd.service"]);
  }
}

interface SamsungUpdate {
  from: string;
  to: string;
  images: string[];
}

// DSRD.xml lists which images update which firmware.
function samsungUpdates(xml: string): SamsungUpdate[] {
  return [...xml.matchAll(/<SSD>([\s\S]*?)<\/SSD>/g)].map(([, block = ""]) => {
    const tag = (name: string) =>
      [...block.matchAll(new RegExp(`<${name}>([^<]*)</${name}>`, "g"))].map(
        ([, value = ""]) => value.trim(),
      );
    return {
      from: tag("CURFW")[0] ?? "",
      to: tag("NEWFW")[0] ?? "",
      images: tag("MFW"),
    };
  });
}

// fumagician picks the image from the first hex digit of bytes 0x20, 0x21,
// 0x24 and 0x25 of this vendor specific security receive.
function samsungVariant(controller: string): string {
  const result = spawnSync(
    "nvme",
    [
      "security-recv",
      controller,
      "--secp=0xfe",
      "--spsp=0x1",
      "--size=4096",
      "--al=4096",
      "--raw-binary",
    ],
    { encoding: "buffer" },
  );
  if (result.status !== 0) {
    throw new Failure(
      `nvme security-recv failed:\n${result.stderr.toString()}`,
    );
  }
  // nvme-cli writes its status line into the binary output.
  const status = Buffer.from("NVME Security Receive Command Success\n");
  const stdout = result.stdout;
  const data = stdout.subarray(0, status.length).equals(status)
    ? stdout.subarray(status.length)
    : stdout;
  const byte = data[0x20];
  if (data.length !== 4096 || byte === undefined) {
    throw new Failure(`unexpected security receive length ${data.length}`);
  }
  return (byte >> 4).toString(16).toUpperCase();
}

function samsungAdapter(device: Device, method: { device: string }): Adapter {
  const identify = () =>
    JSON.parse(
      run("nvme", ["id-ctrl", method.device, "--output-format=json"]),
    ) as { fr: string; mn: string };
  return {
    current: () =>
      existsSync(method.device) ? identify().fr.trim() : undefined,
    flash: () => {
      const { fr, mn } = identify();
      if (!mn.includes("990 PRO")) {
        throw new Failure(`${method.device} is a ${mn.trim()}, not a 990 PRO`);
      }
      const current = fr.trim();
      const update = samsungUpdates(
        readFileSync(join(device.package, "DSRD.xml"), "utf8"),
      ).find((entry) => entry.from === current && entry.to === device.version);
      if (update === undefined) {
        throw new Failure(
          `Samsung lists no update from ${current} to ${device.version}`,
        );
      }
      const variant = samsungVariant(method.device);
      const image = update.images.find((name) =>
        name.startsWith(`${device.version}_${variant}`),
      );
      if (image === undefined) {
        throw new Failure(`no image for hardware variant ${variant}`);
      }
      console.log(`Hardware variant ${variant}, image ${image}`);
      const path = join(device.package, image);
      if (
        !write("nvme", [
          "fw-download",
          method.device,
          `--fw=${path}`,
          "--xfer=16384",
        ])
      ) {
        throw new Failure("nvme fw-download failed");
      }
      // Replace slot 1 and activate on the next reset, like fumagician.
      if (
        !write("nvme", ["fw-commit", method.device, "--slot=1", "--action=1"])
      ) {
        throw new Failure("nvme fw-commit failed");
      }
      console.log("The new firmware becomes active on the next reboot.");
    },
  };
}

// The bcdDevice of the first USB device with these IDs.
function usbRelease(vendorId: string, productId: string): string | undefined {
  const root = "/sys/bus/usb/devices";
  const read = (dir: string, file: string) => {
    try {
      return readFileSync(join(root, dir, file), "utf8").trim();
    } catch {
      return undefined;
    }
  };
  const dir = readdirSync(root).find(
    (entry) =>
      read(entry, "idVendor") === vendorId &&
      read(entry, "idProduct") === productId,
  );
  return dir === undefined ? undefined : read(dir, "bcdDevice");
}

function xmosAdapter(
  device: Device,
  method: Extract<Method, { xmos: unknown }>["xmos"],
): Adapter {
  const env = { XMOSDFU_VID: method.vendorId };
  const current = () => {
    const bcd = usbRelease(method.vendorId, method.productId);
    return bcd === undefined
      ? undefined
      : `${Number.parseInt(bcd.slice(0, 2), 16)}.${bcd.slice(2)}`;
  };
  return {
    current,
    flash: () => {
      if (current() === undefined) {
        throw new Failure(
          `no USB device ${method.vendorId}:${method.productId}`,
        );
      }
      // The factory image stays in flash next to the upgrade image.
      if (
        !write(
          "xmosdfu",
          [method.productId, "--download", join(device.package, method.image)],
          env,
        )
      ) {
        throw new Failure(
          `xmosdfu failed, revert with: XMOSDFU_VID=${method.vendorId} xmosdfu ${method.productId} --revertfactory`,
        );
      }
    },
  };
}

interface Atom {
  version: string;
  // Ends in the BIOS switch position, like 744CHB.22.1.2.12.AS01P.
  model: string;
}

// The first ATOM image in a VBIOS dump or update ROM.
function atom(path: string, type: "amd-gpu-atom" | "amd-gpu-psp"): Atom {
  const xml = run("fwupdtool", ["firmware-parse", path, type]);
  const tag = (name: string) =>
    xml.match(new RegExp(`<${name}>([^<]*)</${name}>`))?.[1];
  const version = tag("version");
  const model = tag("model_name");
  if (version === undefined || model === undefined) {
    throw new Failure(`fwupdtool found no ATOM image in ${path}`);
  }
  return { version, model };
}

function amdGpuAdapter(
  device: Device,
  method: Extract<Method, { amdGpu: unknown }>["amdGpu"],
): Adapter {
  // The running VBIOS of the card with this part number. PCI addresses move
  // when the iGPU gets toggled.
  const running = (): Atom | undefined => {
    const root = "/sys/bus/pci/devices";
    const address = readdirSync(root).find((entry) => {
      try {
        const file = join(root, entry, "vbios_version");
        return readFileSync(file, "utf8").trim() === method.partNumber;
      } catch {
        return false;
      }
    });
    if (address === undefined) return undefined;
    // fwupdtool needs a regular file.
    const dump = join(mkdtempSync(join(tmpdir(), "vbios-")), "vbios.rom");
    writeFileSync(
      dump,
      readFileSync(`/sys/kernel/debug/dri/${address}/amdgpu_vbios`),
    );
    try {
      return atom(dump, "amd-gpu-atom");
    } finally {
      rmSync(dirname(dump), { recursive: true });
    }
  };
  const position = (model: string) => model.slice(model.lastIndexOf("."));
  return {
    current: () => running()?.version,
    flash: () => {
      const model = running()?.model;
      if (model === undefined) {
        throw new Failure(`no GPU with VBIOS part number ${method.partNumber}`);
      }
      const image = method.images
        .map((name) => join(device.package, name))
        .find(
          (path) =>
            position(atom(path, "amd-gpu-psp").model) === position(model),
        );
      if (image === undefined) {
        throw new Failure(`no image for the running VBIOS ${model}`);
      }
      console.log(`Running ${model}, image ${image}`);
      // fwupd reports the part number suffix as the version, which stays the
      // same across VBIOS releases.
      fwupdInstall(method.instanceId, [image], ["--allow-reinstall"]);
      console.log("The new VBIOS becomes active on the next reboot.");
    },
  };
}

function espAdapter(
  name: string,
  device: Device,
  method: { image: string },
  esp: string,
): Adapter {
  return {
    current: () =>
      readFileSync("/sys/class/dmi/id/bios_version", "utf8").trim(),
    flash: () => {
      const dir = join(esp, name);
      if (!dryRun) {
        rmSync(dir, { recursive: true, force: true });
        mkdirSync(dir, { recursive: true });
        copyFileSync(
          join(device.package, method.image),
          join(dir, method.image),
        );
      }
      console.log(
        `${dryRun ? "Would copy" : "Copied"} ${method.image} to ${dir}.`,
      );
      console.log(
        "Reboot into the firmware setup and select it in the flash tool, for ASUS EZ Flash.",
      );
    },
  };
}

function adapter(name: string, device: Device, esp: string): Adapter {
  const method = device.method;
  if ("fwupd" in method) return fwupdAdapter(device, method.fwupd);
  if ("samsungNvme" in method)
    return samsungAdapter(device, method.samsungNvme);
  if ("xmos" in method) return xmosAdapter(device, method.xmos);
  if ("amdGpu" in method) return amdGpuAdapter(device, method.amdGpu);
  return espAdapter(name, device, method.esp, esp);
}

function state(current: string | undefined, version: string): string {
  if (current === undefined) return "not connected";
  return current === version ? "up to date" : "update available";
}

function status(manifest: Manifest): void {
  const rows = Object.entries(manifest.devices).map(([name, device]) => {
    const current = adapter(name, device, manifest.esp).current();
    return [
      name,
      current ?? "-",
      device.version,
      state(current, device.version),
    ];
  });
  const header = ["DEVICE", "CURRENT", "AVAILABLE", "STATE"];
  const widths = header.map((title, column) =>
    Math.max(title.length, ...rows.map((row) => row[column]?.length ?? 0)),
  );
  for (const row of [header, ...rows]) {
    console.log(
      row
        .map((cell, column) => cell.padEnd(widths[column] ?? 0))
        .join("  ")
        .trimEnd(),
    );
  }
}

async function confirm(question: string): Promise<boolean> {
  if (!process.stdin.isTTY) {
    throw new Failure("stdin is not a terminal, pass --yes to flash");
  }
  const prompt = createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  const answer = await prompt.question(`${question} [y/N] `);
  prompt.close();
  return answer.trim().toLowerCase() === "y";
}

async function flash(
  manifest: Manifest,
  name: string,
  flags: string[],
): Promise<void> {
  const device = manifest.devices[name];
  if (device === undefined) {
    throw new Failure(
      `unknown device ${name}, one of: ${Object.keys(manifest.devices).join(", ")}`,
    );
  }
  const target = adapter(name, device, manifest.esp);
  const current = target.current();
  if (current === undefined) {
    throw new Failure(`${name} is not connected`);
  }
  if (current === device.version && !flags.includes("--force")) {
    console.log(`${name} already runs ${current}.`);
    return;
  }
  console.log(`${device.description}: ${current} -> ${device.version}`);
  dryRun = flags.includes("--dry-run");
  if (!dryRun && !flags.includes("--yes") && !(await confirm("Flash it?"))) {
    return;
  }
  target.flash();
}

const usage = `usage: firmware [status]
       firmware flash <device> [--yes] [--force] [--dry-run]`;

const [manifestPath, command = "status", ...rest] = process.argv.slice(2);
if (manifestPath === undefined) {
  throw new Error("the wrapper passes the manifest");
}
const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as Manifest;

try {
  if (process.getuid?.() !== 0) {
    throw new Failure("run it as root, the devices need raw access");
  }
  if (command === "status") {
    status(manifest);
  } else if (command === "flash" && rest[0] !== undefined) {
    await flash(manifest, rest[0], rest.slice(1));
  } else {
    console.error(usage);
    process.exitCode = 2;
  }
} catch (error) {
  if (!(error instanceof Failure)) throw error;
  console.error(`firmware: ${error.message}`);
  process.exitCode = 1;
}
