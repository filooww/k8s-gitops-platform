import http from "k6/http";
import { check, sleep } from "k6";
import { Trend } from "k6/metrics";

// Drives the /work endpoint hard enough to push CPU past the HPA's 60% target,
// so you can watch replicas scale 2 -> 6 while the test runs.
//
//   BASE_URL=http://myapp.localhost:8080 k6 run loadtest/script.js
//
const BASE = __ENV.BASE_URL || "http://myapp.localhost:8080";
// Optional: send an explicit Host header so you can target the ingress by IP
// (e.g. BASE_URL=http://127.0.0.1:8080 HOST_HEADER=myapp.localhost) without
// touching /etc/hosts.
const HOST_HEADER = __ENV.HOST_HEADER || "";
const params = HOST_HEADER ? { headers: { Host: HOST_HEADER } } : {};
const workLatency = new Trend("work_latency_ms");

export const options = {
  scenarios: {
    ramp: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "30s", target: 20 }, // warm up
        { duration: "60s", target: 60 }, // push past HPA target -> scale out
        { duration: "30s", target: 0 },  // cool down -> scale back in
      ],
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],     // <1% errors
    http_req_duration: ["p(95)<2000"],  // p95 under 2s even under load
  },
};

export default function () {
  const res = http.get(`${BASE}/work?iterations=300000`, params);
  workLatency.add(res.timings.duration);
  check(res, { "status is 200": (r) => r.status === 200 });
  sleep(0.2);
}
