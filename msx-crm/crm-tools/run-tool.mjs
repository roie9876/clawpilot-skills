#!/usr/bin/env node
// MSX CRM tool runner - executes a single MCP tool by name with JSON params
// Usage: node crm/run-tool.mjs <tool-name> '<json-params>'
// Example: node crm/run-tool.mjs get_milestones '{"customerKeyword":"Aidoc"}'
//
// SETUP: This tool depends on the MCAPS-IQ library for CRM auth and client.
//   Option A (symlink): ln -s ~/Documents/GitHub/MCAPS-IQ lib/mcaps-iq
//   Option B (clone):   git clone <MCAPS-IQ-repo> lib/mcaps-iq
//   The lib/ directory is .gitignored.

import { createAuthService } from './lib/mcaps-iq/mcp/msx/src/auth.js';
import { createCrmClient } from './lib/mcaps-iq/mcp/msx/src/crm.js';
// ALLOWED_ENTITY_SETS not used; CRM_QUERY_MAX_RECORDS inlined
const CRM_QUERY_MAX_RECORDS = 500;
import { isValidGuid, normalizeGuid, isValidTpid, sanitizeODataString } from './lib/mcaps-iq/mcp/msx/src/validation.js';

const CRM_URL = 'https://microsoftsales.crm.dynamics.com';
const TENANT_ID = '72f988bf-86f1-41af-91ab-2d7cd011db47';

const auth = createAuthService({ crmUrl: CRM_URL, tenantId: TENANT_ID });
const crm = createCrmClient(auth);

const text = (c) => JSON.stringify(c, null, 2);
const error = (msg) => { console.error('ERROR:', msg); process.exit(1); };
const fv = (record, field) => record[`${field}@OData.Community.Display.V1.FormattedValue`] ?? null;
const daysAgo = (days) => { const d = new Date(); d.setDate(d.getDate() - days); return d.toISOString().split('T')[0]; };

const MILESTONE_SELECT = [
  'msp_engagementmilestoneid','msp_milestonenumber','msp_name',
  '_msp_workloadlkid_value','msp_commitmentrecommendation','msp_milestonecategory',
  'msp_monthlyuse','msp_milestonedate','msp_milestonestatus',
  '_ownerid_value','_msp_opportunityid_value',
  'msp_forecastcommentsjsonfield','msp_forecastcomments',
  'msp_milestoneworkload','msp_deliveryspecifiedfield',
  'msp_milestonepreferredazureregion','msp_milestoneazurecapacitytype'
].join(',');

const OPP_SELECT = [
  'opportunityid','name','estimatedclosedate',
  'msp_estcompletiondate','msp_consumptionconsumedrecurring',
  '_ownerid_value','_parentaccountid_value','msp_salesplay'
].join(',');

const ACTIVE_STATUSES = new Set(['Not Started', 'On Track', 'In Progress', 'Blocked', 'At Risk']);

// ── Tool implementations ───────────────────────────────────────

const tools = {
  async crm_whoami() {
    const result = await crm.request('WhoAmI');
    if (!result.ok) error(`WhoAmI failed: ${result.data?.message || result.status}`);
    return result.data;
  },

  async crm_auth_status() {
    const result = await crm.request('WhoAmI');
    if (!result.ok) return { authenticated: false, error: result.data?.message || result.status };
    return { authenticated: true, userId: result.data.UserId, crmUrl: CRM_URL };
  },

  async crm_query({ entitySet, filter, select, orderby, top, expand }) {
    if (!entitySet) error('entitySet is required');
    const query = {};
    if (filter) query.$filter = filter;
    if (select) query.$select = select;
    if (orderby) query.$orderby = orderby;
    if (top) query.$top = String(Math.min(top, CRM_QUERY_MAX_RECORDS));
    if (expand) query.$expand = expand;
    const result = await crm.requestAllPages(entitySet, { query, maxRecords: CRM_QUERY_MAX_RECORDS });
    if (!result.ok) error(`Query failed (${result.status}): ${result.data?.message}`);
    const records = result.data?.value || (result.data ? [result.data] : []);
    return { count: records.length, value: records };
  },

  async crm_get_record({ entitySet, id, select }) {
    if (!entitySet || !id) error('entitySet and id are required');
    const nid = normalizeGuid(id);
    if (!isValidGuid(nid)) error('Invalid GUID');
    const query = {};
    if (select) query.$select = select;
    const result = await crm.request(`${entitySet}(${nid})`, { query });
    if (!result.ok) error(`Get record failed (${result.status}): ${result.data?.message}`);
    return result.data;
  },

  async list_opportunities({ accountIds, customerKeyword, includeCompleted }) {
    let resolvedIds = accountIds ? accountIds.map(normalizeGuid).filter(isValidGuid) : [];
    if (!resolvedIds.length && customerKeyword) {
      const sanitized = sanitizeODataString(customerKeyword.trim());
      const acctResult = await crm.requestAllPages('accounts', {
        query: { $filter: `contains(name,'${sanitized}')`, $select: 'accountid,name', $top: '50' }
      });
      const accounts = acctResult.ok ? (acctResult.data?.value || []) : [];
      if (!accounts.length) return { count: 0, opportunities: [], message: `No accounts found matching '${customerKeyword}'` };
      resolvedIds = accounts.map(a => a.accountid);
    }
    if (!resolvedIds.length) error('Provide accountIds array or customerKeyword');
    const chunks = [];
    for (let i = 0; i < resolvedIds.length; i += 25) chunks.push(resolvedIds.slice(i, i + 25));
    const allOpps = [];
    for (const chunk of chunks) {
      let filter = `(${chunk.map(id => `_parentaccountid_value eq '${id}'`).join(' or ')}) and statecode eq 0`;
      if (!includeCompleted) filter += ` and msp_estcompletiondate ge ${daysAgo(30)}`;
      const result = await crm.requestAllPages('opportunities', {
        query: { $filter: filter, $select: OPP_SELECT, $orderby: 'name' }
      });
      if (result.ok && result.data?.value) allOpps.push(...result.data.value);
    }
    return { count: allOpps.length, opportunities: allOpps };
  },

  async get_my_active_opportunities({ customerKeyword } = {}) {
    const whoAmI = await crm.request('WhoAmI');
    if (!whoAmI.ok || !whoAmI.data?.UserId) error('WhoAmI failed');
    const userId = normalizeGuid(whoAmI.data.UserId);
    const cutoff = daysAgo(30);
    // Direct ownership
    const ownedResult = await crm.requestAllPages('opportunities', {
      query: { $filter: `_ownerid_value eq '${userId}' and statecode eq 0 and msp_estcompletiondate ge ${cutoff}`, $select: OPP_SELECT, $orderby: 'name' }
    });
    let opps = ownedResult.ok ? (ownedResult.data?.value || []) : [];
    // Deal team membership
    try {
      const dtResult = await crm.requestAllPages('msp_dealteams', {
        query: { $filter: `_msp_userid_value eq '${userId}'`, $select: '_msp_opportunityid_value', $top: '200' }
      });
      if (dtResult.ok && dtResult.data?.value?.length) {
        const dtOppIds = dtResult.data.value.map(d => d._msp_opportunityid_value).filter(Boolean);
        const unique = [...new Set(dtOppIds)].filter(id => !opps.some(o => o.opportunityid === id));
        if (unique.length) {
          for (let i = 0; i < unique.length; i += 25) {
            const chunk = unique.slice(i, i + 25);
            const dtFilter = `(${chunk.map(id => `opportunityid eq '${id}'`).join(' or ')}) and statecode eq 0 and msp_estcompletiondate ge ${cutoff}`;
            const r = await crm.requestAllPages('opportunities', { query: { $filter: dtFilter, $select: OPP_SELECT, $orderby: 'name' } });
            if (r.ok && r.data?.value) opps.push(...r.data.value);
          }
        }
      }
    } catch {}
    if (customerKeyword) {
      const kw = customerKeyword.toLowerCase();
      opps = opps.filter(o => (fv(o, '_parentaccountid_value') || '').toLowerCase().includes(kw));
    }
    return { count: opps.length, opportunities: opps };
  },

  async get_milestones({ customerKeyword, opportunityKeyword, opportunityId, opportunityIds, milestoneNumber, milestoneId, ownerId, mine, statusFilter, keyword, format, includeTasks }) {
    if (mine === true && statusFilter === undefined) statusFilter = 'active';

    // Direct GUID lookup
    if (milestoneId) {
      const nid = normalizeGuid(milestoneId);
      if (!isValidGuid(nid)) error('Invalid milestoneId GUID');
      const result = await crm.request(`msp_engagementmilestones(${nid})`, { query: { $select: MILESTONE_SELECT } });
      if (!result.ok) error(`Milestone lookup failed (${result.status}): ${result.data?.message}`);
      return result.data;
    }

    let resolvedOppIds = null;
    if (customerKeyword) {
      const sanitized = sanitizeODataString(customerKeyword.trim());
      const acctResult = await crm.requestAllPages('accounts', { query: { $filter: `contains(name,'${sanitized}')`, $select: 'accountid,name', $top: '50' } });
      const accounts = acctResult.ok ? (acctResult.data?.value || []) : [];
      if (!accounts.length) return { count: 0, milestones: [], message: `No accounts found matching '${customerKeyword}'` };
      const acctIds = accounts.map(a => a.accountid);
      const cutoff = daysAgo(30);
      const allOpps = [];
      for (let i = 0; i < acctIds.length; i += 25) {
        const chunk = acctIds.slice(i, i + 25);
        const acctFilter = `(${chunk.map(id => `_parentaccountid_value eq '${id}'`).join(' or ')}) and statecode eq 0 and msp_estcompletiondate ge ${cutoff}`;
        const r = await crm.requestAllPages('opportunities', { query: { $filter: acctFilter, $select: 'opportunityid,name', $orderby: 'name' } });
        if (r.ok && r.data?.value) allOpps.push(...r.data.value);
      }
      if (!allOpps.length) return { count: 0, milestones: [], message: `No active opportunities for customer '${customerKeyword}'` };
      resolvedOppIds = allOpps.map(o => o.opportunityid);
    }

    if (!resolvedOppIds && opportunityKeyword) {
      const sanitized = sanitizeODataString(opportunityKeyword.trim());
      const cutoff = daysAgo(30);
      const r = await crm.requestAllPages('opportunities', {
        query: { $filter: `contains(name,'${sanitized}') and statecode eq 0 and msp_estcompletiondate ge ${cutoff}`, $select: 'opportunityid,name', $orderby: 'name', $top: '50' }
      });
      const opps = r.ok ? (r.data?.value || []) : [];
      if (!opps.length) return { count: 0, milestones: [], message: `No active opportunities matching '${opportunityKeyword}'` };
      resolvedOppIds = opps.map(o => o.opportunityid);
    }

    if (resolvedOppIds) {
      const merged = resolvedOppIds;
      if (opportunityIds?.length) merged.push(...opportunityIds);
      if (opportunityId) merged.push(opportunityId);
      opportunityIds = merged;
      opportunityId = undefined;
    }

    let filter;
    if (milestoneNumber) {
      filter = `msp_milestonenumber eq '${sanitizeODataString(milestoneNumber.trim())}'`;
    } else if (opportunityIds?.length) {
      const validIds = opportunityIds.map(normalizeGuid).filter(isValidGuid);
      if (!validIds.length) error('No valid opportunity GUIDs');
      const allMs = [];
      for (let i = 0; i < validIds.length; i += 25) {
        const chunk = validIds.slice(i, i + 25);
        const chunkFilter = chunk.map(id => `_msp_opportunityid_value eq '${id}'`).join(' or ');
        const r = await crm.requestAllPages('msp_engagementmilestones', { query: { $filter: chunkFilter, $select: MILESTONE_SELECT, $orderby: 'msp_milestonedate' } });
        if (r.ok && r.data?.value) allMs.push(...r.data.value);
      }
      let milestones = allMs;
      if (statusFilter === 'active') milestones = milestones.filter(m => ACTIVE_STATUSES.has(fv(m, 'msp_milestonestatus')));
      if (keyword) { const kw = keyword.toLowerCase(); milestones = milestones.filter(m => (m.msp_name||'').toLowerCase().includes(kw) || (fv(m,'_msp_opportunityid_value')||'').toLowerCase().includes(kw)); }
      return { count: milestones.length, milestones };
    } else if (opportunityId) {
      const nid = normalizeGuid(opportunityId);
      if (!isValidGuid(nid)) error('Invalid opportunityId GUID');
      filter = `_msp_opportunityid_value eq '${nid}'`;
    } else if (ownerId) {
      const nid = normalizeGuid(ownerId);
      if (!isValidGuid(nid)) error('Invalid ownerId GUID');
      filter = `_ownerid_value eq '${nid}'`;
    } else if (mine === true) {
      const whoAmI = await crm.request('WhoAmI');
      if (!whoAmI.ok || !whoAmI.data?.UserId) error('WhoAmI failed');
      filter = `_ownerid_value eq '${normalizeGuid(whoAmI.data.UserId)}'`;
    } else {
      error('Scoping required: provide customerKeyword, opportunityKeyword, opportunityId, opportunityIds, milestoneNumber, milestoneId, ownerId, or mine=true');
    }

    const result = await crm.requestAllPages('msp_engagementmilestones', { query: { $filter: filter, $select: MILESTONE_SELECT, $orderby: 'msp_milestonedate' } });
    if (!result.ok) error(`Get milestones failed (${result.status}): ${result.data?.message}`);
    let milestones = result.data?.value || [];
    if (statusFilter === 'active') milestones = milestones.filter(m => ACTIVE_STATUSES.has(fv(m, 'msp_milestonestatus')));
    if (keyword) { const kw = keyword.toLowerCase(); milestones = milestones.filter(m => (m.msp_name||'').toLowerCase().includes(kw) || (fv(m,'_msp_opportunityid_value')||'').toLowerCase().includes(kw)); }
    return { count: milestones.length, milestones };
  },

  async list_accounts_by_tpid({ tpid }) {
    if (!tpid) error('tpid is required');
    const result = await crm.requestAllPages('accounts', {
      query: { $filter: `msp_tpid eq '${sanitizeODataString(String(tpid))}'`, $select: 'accountid,name,msp_tpid', $orderby: 'name' }
    });
    if (!result.ok) error(`Account query failed (${result.status}): ${result.data?.message}`);
    return { count: (result.data?.value || []).length, accounts: result.data?.value || [] };
  },

  async get_milestone_activities({ milestoneId, milestoneIds }) {
    const ids = milestoneIds?.length ? milestoneIds : milestoneId ? [milestoneId] : [];
    if (!ids.length) error('milestoneId or milestoneIds required');
    const validIds = ids.map(normalizeGuid).filter(isValidGuid);
    const allTasks = [];
    for (let i = 0; i < validIds.length; i += 25) {
      const chunk = validIds.slice(i, i + 25);
      const filter = chunk.map(id => `_regardingobjectid_value eq '${id}'`).join(' or ');
      const r = await crm.requestAllPages('tasks', { query: { $filter: filter, $select: 'activityid,subject,description,scheduledend,statuscode,statecode,_regardingobjectid_value,_ownerid_value,msp_taskcategory', $orderby: 'scheduledend' } });
      if (r.ok && r.data?.value) allTasks.push(...r.data.value);
    }
    return { count: allTasks.length, tasks: allTasks };
  },

  async find_milestones_needing_tasks({ customerKeyword, opportunityKeyword, mine }) {
    // Get milestones then filter to those without tasks
    const msResult = await tools.get_milestones({ customerKeyword, opportunityKeyword, mine, statusFilter: 'active' });
    if (!msResult.milestones?.length) return { count: 0, milestones: [], message: 'No active milestones found' };
    const msIds = msResult.milestones.map(m => m.msp_engagementmilestoneid).filter(Boolean);
    // Check which have tasks
    const taskResult = await crm.requestAllPages('tasks', {
      query: { $filter: msIds.map(id => `_regardingobjectid_value eq '${id}'`).join(' or '), $select: '_regardingobjectid_value', $top: '500' }
    });
    const withTasks = new Set((taskResult.ok ? taskResult.data?.value || [] : []).map(t => t._regardingobjectid_value));
    const needingTasks = msResult.milestones.filter(m => !withTasks.has(m.msp_engagementmilestoneid));
    return { count: needingTasks.length, milestones: needingTasks };
  },

  async list_pending_operations() {
    return { message: 'Approval queue is only available in the full MCP server session. Use the MCP server directly for write operations.' };
  },

  // ── Write operations ─────────────────────────────────────────

  async create_task({ subject, description, scheduledend, milestoneId, taskcategory, ownerId, duration, priority, relatedLink }) {
    if (!subject) error('subject is required');
    if (!milestoneId) error('milestoneId is required');
    const nid = normalizeGuid(milestoneId);
    if (!isValidGuid(nid)) error('Invalid milestoneId GUID');

    const body = {
      subject,
      ...(description && { description }),
      ...(scheduledend && { scheduledend }),
      ...(taskcategory !== undefined && { msp_taskcategory: taskcategory }),
      ...(duration !== undefined && { actualdurationminutes: duration }),
      ...(priority !== undefined && { prioritycode: priority }),
      ...(relatedLink && { msp_relatedlink: relatedLink }),
      'regardingobjectid_msp_engagementmilestone@odata.bind': `/msp_engagementmilestones(${nid})`
    };

    if (ownerId) {
      const oid = normalizeGuid(ownerId);
      if (isValidGuid(oid)) body['ownerid@odata.bind'] = `/systemusers(${oid})`;
    }

    const result = await crm.request('tasks', { method: 'POST', body });
    if (!result.ok) error(`Create task failed (${result.status}): ${result.data?.message}`);

    // CRM returns 204 with no body on success; query back the created task
    const verify = await crm.requestAllPages('tasks', {
      query: {
        $filter: `subject eq '${sanitizeODataString(subject)}' and _regardingobjectid_value eq '${nid}'`,
        $select: 'activityid,subject,scheduledend,statuscode,createdon',
        $orderby: 'createdon desc',
        $top: '1'
      }
    });
    const created = verify.ok ? verify.data?.value?.[0] : null;

    return {
      success: true,
      subject,
      milestoneId: nid,
      taskId: created?.activityid || null,
      createdOn: created?.createdon || null
    };
  },

  async update_task({ taskId, subject, description, scheduledend, statuscode, statecode, duration }) {
    if (!taskId) error('taskId is required');
    const nid = normalizeGuid(taskId);
    if (!isValidGuid(nid)) error('Invalid taskId GUID');

    const body = {};
    if (subject !== undefined) body.subject = subject;
    if (description !== undefined) body.description = description;
    if (scheduledend !== undefined) body.scheduledend = scheduledend;
    if (statuscode !== undefined) body.statuscode = statuscode;
    if (statecode !== undefined) body.statecode = statecode;
    if (duration !== undefined) body.actualdurationminutes = duration;

    if (!Object.keys(body).length) error('No fields to update');

    const result = await crm.request(`tasks(${nid})`, { method: 'PATCH', body });
    if (!result.ok) error(`Update task failed (${result.status}): ${result.data?.message}`);

    return { success: true, taskId: nid, updated: Object.keys(body) };
  },

  async delete_task({ taskId }) {
    if (!taskId) error('taskId is required');
    const nid = normalizeGuid(taskId);
    if (!isValidGuid(nid)) error('Invalid taskId GUID');

    const result = await crm.request(`tasks(${nid})`, { method: 'DELETE' });
    if (!result.ok) error(`Delete task failed (${result.status}): ${result.data?.message}`);

    return { success: true, taskId: nid, deleted: true };
  }
};

// ── Main ───────────────────────────────────────────────────────
const [toolName, paramsJson] = process.argv.slice(2);
if (!toolName) {
  console.log('Available tools:', Object.keys(tools).join(', '));
  process.exit(0);
}

const fn = tools[toolName];
if (!fn) {
  console.error(`Unknown tool: ${toolName}. Available: ${Object.keys(tools).join(', ')}`);
  process.exit(1);
}

const params = paramsJson ? JSON.parse(paramsJson) : {};
try {
  const result = await fn(params);
  console.log(text(result));
} catch (e) {
  console.error('Error:', e.message);
  process.exit(1);
}
