/** region-impact.lsl **
* v 0.1.0
* CC0 1.0 Universal
* https://github.com/spookerton/sl-utils
* 
* Agent region performance impact data gatherer.
* Only a couple of assumptions are made - bring
* your own handling behavior.
*/

list details;
float scriptTime;
float scriptMemory;
float serverCost;
float streamCost;
float physicsCost;

updateDetails(key target, integer clear) {
  if (clear) {
    scriptTime = 0;
    scriptMemory = 0;
    serverCost = 0;
    streamCost = 0;
    physicsCost = 0;
  }
  details = llGetObjectDetails(target, [
    OBJECT_SCRIPT_TIME,
    OBJECT_SCRIPT_MEMORY,
    OBJECT_SERVER_COST,
    OBJECT_STREAMING_COST,
    OBJECT_PHYSICS_COST,
    OBJECT_ROOT
  ]);
  scriptTime += llList2Float(details, 0);
  scriptMemory += llList2Float(details, 1);
  serverCost += llList2Float(details, 2);
  streamCost += llList2Float(details, 3);
  physicsCost += llList2Float(details, 4);
}

integer imin(integer a, integer b) {
  if (a > b)
    return b;
  return a;
}

default {
  state_entry() {
    list agents;
    integer len;
    integer i;
    key agent;
    key root;
    string agentLegacyName;
    string agentName;
    string rootName;
    integer finalScriptTime;
    integer finalScriptMemory;
    integer finalServerCost;
    integer finalStreamCost;
    integer finalPhysicsCost;
    integer costMap;
    string finalData;

    do {
      agents = llGetAgentList(AGENT_LIST_REGION, []);
      len = llGetListLength(agents);
      for (i = 0; i < len; ++i) {
        agent = llList2Key(agents, i);
        agentLegacyName = llKey2Name(agent);
        if (agentLegacyName == "") // If they're not in the region anymore ...
          jump skipThisAgent; // Skip doing work. Thanks for no continue, LSL
        updateDetails(agent, TRUE); // Clear and update the raw perf details for agent
        agentName = llGetUsername(agent);
        if (agentName == "") // agent's username is unavailable, fall back to legacy name
          agentName = llReplaceSubString(agentLegacyName, " ", ".", 1);
        root = llList2Key(details, 5);
        if (root == agent)
          rootName = "";
        else { // agent is sitting on something - collect its info too
          rootName = llGetSubString(llKey2Name(root), 0, 16);
          rootName = llReplaceSubString(rootName, " ", "_", 0);
          updateDetails(root, FALSE);
        }
        details = []; //don't bother holding finished data

        /** HEY! **
        * At this point you might decide if it's worth emitting the values at all by
        * looking at the raw numbers built by updateDetails and, if it's not, jumping
        * to skipThisAgent. You might also want to decide that at the end though, and
        * emit potential issues on one channel and *all* values on another for metrics.
        * It may also be useful to collect a list of recent results to emit via HTTP for
        * offsite handling - the peak memory usage of this script in a 15 person region
        * is about 8KiB and final outputs are small, so there's room to spare.
        */

        /**
        * - script time 9 bits, from 0 to 511 μs
        *   A region at 15ms script time is at 15000μs. Generally we want this as low as
        *   possible. It's worth noting that this value is the 30 minute average of both
        *   the agent and potentially a vehicle, so it may vary quite significantly, but
        *   a virtuous person might aim for under 100. 250 is becoming quite unfriendly.
        */
        finalScriptTime = imin(llRound(scriptTime * 1e6), 0x1ff);

        /**
        * - script memory 9 bits, from 0 to 511 2daKiB - 511 is ~10MiB
        *   Same again. 1MiB is 16 full size mono scripts. While this doesn't reflect current
        *   actually allocated memory, it does show the worst case usage. Higher potential
        *   allocation generally means a worse simulator hitch when a user enters. For any
        *   combat region the aim should be as low as possible, and for multi-region areas
        *   much more so.
        */
        finalScriptMemory = imin(llRound(scriptMemory / 20480), 0x1ff);

        /**
        * - server cost 4 bits, from 0 to 15 units
        *   https://wiki.secondlife.com/wiki/Mesh/Mesh_Server_Weight
        *   This can be scaled where finalServerCost is set; I've done no no testing for what
        *   might constitute "bad", or even if it's worth keeping track of given its somewhat
        *   opaque nature.
        */
        finalServerCost = imin(llRound(serverCost), 0xf);

        /**
        * - stream cost 5 bits, from 0 to 63 units
        *   https://wiki.secondlife.com/wiki/Mesh/Download_Weight
        *   Can be roughly equated to render cost and exactly equated to download size. Higher
        *   stream costs will be associated with worse viewer performance when the related agent
        *   or agent+vehicle are visible, and may cause framerate drops on LOD thresholds. Lower
        *   is better. Currently quartered to scale better - start worrying over 32.
        */
        finalStreamCost = imin(llRound(streamCost / 4), 0x1f);

        /**
        * - physics cost 5 bits, from 0 to 63 units
        *   https://wiki.secondlife.com/wiki/Mesh/Mesh_physics
        *   Bit of a complicated metric. Lower is better, but I've done very little eyeballing
        *   to know where bad and good are. This may need different scaling.
        */
        finalPhysicsCost = imin(llRound(physicsCost * 10), 0x1f);

        // Pack the values into an int ...
        costMap = finalScriptTime
                | finalScriptMemory << 9
                | finalServerCost << 18
                | finalStreamCost << 22
                | finalPhysicsCost << 27;

        /**
        * Concat the int as trimmed base64 value with the best-effort agent name
        * (either username or legacy name with " " changed to ".") and the first
        * 16 characters of their vehicle's name, if any, with " " changed to "_".
        * To get the values back out, do base64toint(the_value + "==") and then
        * >>& unpack the numbers.
        */
        finalData = (string)[
          llGetSubString(llIntegerToBase64(costMap), 0, -3), " ",
          agentName, " ",
          rootName
        ];

        // And if we wanted to emit the result, it's as simple as:
        //llRegionSay(9008456, finalData);

        @skipThisAgent;
        llSleep(1);
      }
    } while (TRUE);
  }
}
