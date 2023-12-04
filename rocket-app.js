const http = require("http");
const { exec } = require("child_process");
const os = require("os");
const process = require("process");
const { Buffer } = require("buffer");

const API_URL = "{api_url}";
const API_TOKEN = "{api_token}";

var settings = {
  calc_traffic: 0,
};

const runCmd = (command) => {
  return new Promise((resolve, reject) => {
    exec(command, (error, stdout, stderr) => {
      if (error) {
        resolve({ stdout: "", stderr: "" });
      }
      if (stdout) {
        stdout = stdout.trim();
      }
      resolve({ stdout, stderr });
    });
  });
};

const helpers = {
  snaitizeCmdOut: (output) => {
    output = output.replaceAll("\n", output);
    output = output.trim(output);
    return output;
  },
  calculateCPUsage: async () => {
    const { stdout } = await runCmd('top -bn1 | grep "%Cpu(s)"');
    const cpuUsage = parseFloat(stdout.split(",")[0].split(":")[1].trim());
    return cpuUsage;
  },
  getHDDInfo: async () => {
    const rootPath = "/";
    const result = {
      total: 0,
      used: 0,
      free: 0,
      precent: 0,
    };

    const { stdout } = await runCmd(`df -h ${rootPath}`);
    if (stdout) {
      const outputLines = stdout.split("\n");
      const [_, total, used, free, precent] = outputLines[1].split(/\s+/);
      result.total = total;
      result.used = used;
      result.free = free;
      result.precent = precent;
    }

    return result;
  },
  sysResources: async () => {
    const cpus = os.cpus();
    const uptime = os.uptime();
    const loadavg = os.loadavg();
    const freemem = os.freemem();
    const totalmem = os.totalmem();
    const cpuUsage = await helpers.calculateCPUsage();
    const users = await helpers.getUsersList();
    const usedMemory = totalmem - freemem;
    const totalDownload = await helpers.getDownloadUsage();
    const totalUpload = await helpers.getUploadUsage();
    const appStatus = await helpers.getRocketAppStatus();

    const traffic = {
      download: totalDownload,
      upload: totalUpload,
      total: totalDownload + totalUpload,
    };
    const cpuInfo = {
      cores: cpus.length,
      uptime: uptime,
      loadavg: loadavg,
      usage: cpuUsage,
    };
    const memeoryInfo = {
      total: totalmem,
      free: freemem,
      used: usedMemory,
    };
    const hddInfo = await helpers.getHDDInfo();
    const result = {
      cpu: cpuInfo,
      memeory: memeoryInfo,
      hdd: hddInfo,
      users,
      traffic,
      app_status: appStatus,
    };
    return result;
  },
  createUser: async (username, password) => {
    const addUserCommand = `sudo adduser ${username} --force-badname --shell /usr/sbin/nologin &`;
    const setPasswordCommand = `sudo passwd ${username} <<!\n${password}\n${password}\n!`;
    const fullCommand = `${addUserCommand}\nwait\n${setPasswordCommand}`;
    await runCmd(fullCommand);
  },
  killUser: async (username) => {
    await runCmd(`sudo killall -u ${username}`);
    await runCmd(`sudo pkill -u ${username}`);
    await runCmd(`sudo timeout 10 pkill -u ${username}`);
    await runCmd(`sudo timeout 10 killall -u ${username}`);
  },
  removeUser: async (username) => {
    const cmd = `sudo userdel -r ${username}`;
    await runCmd(cmd);
  },
  getUsersList: async () => {
    const { stdout } = await runCmd("ls /home");
    let users = [];
    if (stdout) {
      const outputArray = stdout.split(/\r\n|\n|\r/);
      const invalidUsers = ["videocall", "ocean"];
      users = outputArray.filter((user) => !invalidUsers.includes(user)).map((user) => user.trim());
    }
    return users;
  },
  isNumeric: (value) => {
    return /^\d+$/.test(value);
  },
  getDownloadUsage: async () => {
    let download = 0;

    const { stdout } = await runCmd("netstat -e -n -i | grep 'RX packets' | grep -v 'RX packets 0' | grep -v ' B)' | awk '{print $5}'");
    if (stdout) {
      const outputArray = stdout.split(/\r\n|\n|\r/);
      outputArray.forEach((value) => {
        download += parseInt(value);
      });
    }

    return download;
  },
  getUploadUsage: async () => {
    let upload = 0;
    const { stdout } = await runCmd("netstat -e -n -i | grep 'TX packets' | grep -v 'TX packets 0' | grep -v ' B)' | awk '{print $5}'");
    if (stdout) {
      const outputArray = stdout.split(/\r\n|\n|\r/);
      console.log("outputArray",outputArray);
      outputArray.forEach((value) => {
        upload += parseInt(value);
      });
    }
    return upload;
  },
  getRocketAppStatus: async () => {
    const cmd = `sudo supervisorctl status rocketApp | awk '{print  $2}'`;
    const { stdout } = await runCmd(cmd);
    return stdout;
  },
};

const apiActions = {
  createUser: async (pdata) => {
    const { username, password } = pdata;
    await helpers.createUser(username, password);
  },
  removeUser: async (pdata) => {
    const { username } = pdata;
    await helpers.removeUser(username);
  },
  updateUser: async (pdata) => {
    const { username, password } = pdata;
    await helpers.killUser(username);
    await helpers.removeUser(username);
    await helpers.createUser(username, password);
  },
  killUserByPid: async (pdata) => {
    const { pid } = pdata;
    const command = `pstree -p ${pid} | awk -F\"[()]\" '/sshd/ {print $4}'`;
    const { stdout } = await runCmd(command);
    if (stdout) {
      const procId = stdout;
      await runCmd(`sudo kill -9 ${procId}`);
      await runCmd(`sudo timeout 10 kill -9 ${procId}`);
    }
  },
};

const sendToApi = (endpoint, pdata = false) => {
  return new Promise((resolve, reject) => {
    const urlPath = `/sapi/${endpoint}?token=${API_TOKEN}`;
    const baseUrl = API_URL.replace(/^https?:\/\//, "");

    const options = {
      hostname: baseUrl,
      port: 80,
      path: urlPath,
      method: "GET",
      headers: {
        "Content-Type": "application/json",
      },
    };
    if (pdata) {
      options.method = "POST";
    }

    const req = http.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => {
        data += chunk;
      });
      res.on("end", () => {
        resolve(data);
      });
    });

    req.on("error", (error) => {
      reject(error);
    });

    if (pdata) {
      req.write(pdata);
    }

    req.end();
  });
};

const LoopMethods = {
  doStart: async () => {
    LoopMethods.getSettings();
    LoopMethods.sendTraffic();
    LoopMethods.resetSshSerivces();
    LoopMethods.removeAuthLog();
    LoopMethods.sendUsersAuthPids();

    console.log("start loop methods");
  },
  getSettings: async () => {
    sendToApi("settings")
      .then((result) => {
        result = JSON.parse(result);
        settings.calc_traffic = result.servers_calc_traffic;
        console.log("getSettings");
        setTimeout(LoopMethods.getSettings, 1800 * 1000);
      })
      .catch((err) => {
        console.log("getSettings");
        setTimeout(LoopMethods.getSettings, 1800 * 1000);
      });
  },
  sendTraffic: async () => {
    const command = "sudo nethogs -j -v3 -c6";
    runCmd(command)
      .then((res) => {
        runCmd(`sudo pkill nethogs`);
        const { stdout } = res;

        if (stdout) {
          const base64Encoded = Buffer.from(stdout).toString("base64");
          const pdata = JSON.stringify({ data: base64Encoded });
          sendToApi("traffics", pdata);
        }
        runCmd("pgrep nethogs").then((result) => {
          const { stdout } = result;
          if (stdout) {
            runCmd(`sudo kill -9 ${stdout}`);
            runCmd("sudo killall -9 nethogs");
          }
        });
        console.log("sendTraffic");
        setTimeout(LoopMethods.sendTraffic, 5000);
      })
      .catch((err) => {
        console.log("sendTraffic");
        setTimeout(LoopMethods.sendTraffic, 5000);
      });
  },
  resetSshSerivces: async () => {
    runCmd("sudo service ssh restart");
    runCmd("sudo service sshd restart");
    console.log("restart ssh");
    setTimeout(LoopMethods.resetSshSerivces, 1800 * 1000);
  },
  removeAuthLog: async () => {
    runCmd("sudo truncate -s 0 /var/log/auth.log");
    console.log("truncate auth.log");
    setTimeout(LoopMethods.removeAuthLog, 3600 * 1000);
  },
  sendUsersAuthPids: async () => {
    runCmd(`ps aux | grep priv | awk '{print $2}'`)
      .then((result) => {
        const { stdout } = result;
        if (stdout) {
          const base64Encoded = Buffer.from(stdout).toString("base64");
          const pdata = JSON.stringify({ pid_list: base64Encoded });
          sendToApi("upids", pdata);
        }
        console.log("send Pids");
        setTimeout(LoopMethods.sendUsersAuthPids, 10 * 1000);
      })
      .catch((err) => {
        console.log("send Pids");
        setTimeout(LoopMethods.sendUsersAuthPids, 10 * 1000);
      });
  },
};

const hanldeApiAction = async (pdata) => {
  try {
    const action = pdata.action;
    if (action === "create-user") {
      apiActions.createUser(pdata);
    } else if (action === "remove-user") {
      apiActions.removeUser(pdata);
    } else if (action === "resources") {
      return await helpers.sysResources();
    } else if (action === "kill-upid") {
      apiActions.killUserByPid(pdata);
    } else if (action === "update-user") {
      apiActions.updateUser(pdata);
    }
  } catch (err) {
    console.log("error hanldeApiAction", err);
  }
};

const server = http.createServer(async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  const urlPath = req.url;
  const sendMethod = req.method;
  const authToken = req.headers["x-auth"];

  if (authToken !== "123456") {
    res.writeHead(401, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Unauthorized" }));
    return;
  }

  if (sendMethod === "POST" && urlPath === "/") {
    var pdata = "";
    const readBody = () =>
      new Promise((resolve) => {
        req.on("data", (chunk) => {
          pdata += chunk.toString();
        });

        req.on("end", () => {
          resolve();
        });
      });
    await readBody();

    //handle actions
    if (pdata) {
      pdata = JSON.parse(pdata);
      console.log("pdata", pdata);
      try {
        var result = await hanldeApiAction(pdata);
        res.writeHead(200, { "Content-Type": "application/json" });
        if (!result) {
          result = { status: "success" };
        }
        return res.end(JSON.stringify(result));
      } catch (err) {}
    }

    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end("");
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  return res.end("Not Found");
});

process.on("unhandledRejection", (error) => {
  console.log("unhandledRejection: " + JSON.stringify(error.stack));
});

process.on("uncaughtException", (error) => {
  console.log("uncaughtException: " + JSON.stringify(error.stack));
});

server.listen(3000, "localhost", () => {
  console.log("Listening for request");

  LoopMethods.doStart();
});