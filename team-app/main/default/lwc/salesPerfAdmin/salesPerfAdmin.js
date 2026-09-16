import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getAccessMatrix from '@salesforce/apex/GtmTeamAccessController.getAccessMatrix';
import searchUsers from '@salesforce/apex/GtmTeamAccessController.searchUsers';
import getUserGrant from '@salesforce/apex/GtmTeamAccessController.getUserGrant';
import rolePreset from '@salesforce/apex/GtmTeamAccessController.rolePreset';
import saveGrant from '@salesforce/apex/GtmTeamAccessController.saveGrant';
import assignAppPermset from '@salesforce/apex/GtmTeamAccessController.assignAppPermset';
import deleteGrant from '@salesforce/apex/GtmTeamAccessController.deleteGrant';
import revokeAppPermset from '@salesforce/apex/GtmTeamAccessController.revokeAppPermset';

const ROLE_MEMBER = 'Team_Member';

export default class SalesPerfAdmin extends LightningElement {
    wired;
    info;
    error;
    notice;
    selectedUserId = '';
    selectedName = '';
    role = ROLE_MEMBER;
    busy = false;
    searchTerm = '';
    hits = [];
    searched = false;
    editingExisting = false;
    tabItems = [];
    activityItems = [];
    searchTimer;

    @wire(getAccessMatrix)
    wire(result) {
        this.wired = result;
        if (result.data) {
            this.info = this.decorate(result.data);
            this.error = undefined;
            if (!this.selectedUserId && !this.editingExisting && this.tabItems.length === 0) {
                this.tabItems = this.copyItems(result.data.tabCatalog);
                this.activityItems = this.copyItems(result.data.activityCatalog);
            }
        } else if (result.error) {
            this.error = this.msg(result.error);
        }
    }

    decorate(data) {
        const users = (data.users || []).map((u) => ({
            ...u,
            rowClass: u.id === this.selectedUserId ? 'is-edit' : ''
        }));
        return { ...data, users };
    }

    copyItems(items) {
        return (items || []).map((i) => ({ key: i.key, label: i.label, checked: !!i.checked }));
    }

    msg(e) {
        return (e && e.body && e.body.message) || 'Something went wrong.';
    }

    get permSetName() {
        return (this.info && this.info.permSet) || '';
    }
    get viewerPermSetName() {
        return (this.info && this.info.viewerPermSet) || '';
    }
    get hasUsers() {
        return this.info && this.info.users && this.info.users.length > 0;
    }
    get userCount() {
        return this.hasUsers ? this.info.users.length : 0;
    }
    get canManage() {
        return !!(this.info && this.info.canManage);
    }
    get editBadge() {
        return this.info && this.info.editInCall ? 'granted' : 'denied';
    }
    get overrideBadge() {
        return this.info && this.info.overrideClass ? 'granted' : 'denied';
    }
    get apexBadge() {
        return this.info && this.info.apexAccess ? 'granted' : 'denied';
    }
    get editClass() {
        return 'pill ' + (this.info && this.info.editInCall ? 'p-hi' : 'p-ex');
    }
    get overrideClass() {
        return 'pill ' + (this.info && this.info.overrideClass ? 'p-hi' : 'p-ex');
    }
    get apexClass() {
        return 'pill ' + (this.info && this.info.apexAccess ? 'p-hi' : 'p-ex');
    }
    get showHits() {
        return this.hits.length > 0 && !this.selectedUserId;
    }
    get searchEmpty() {
        return this.searched && this.hits.length === 0 && this.searchTerm.trim().length >= 2 && !this.selectedUserId;
    }
    get showEditor() {
        return this.canManage && (!!this.selectedUserId || this.editingExisting);
    }
    get editorTitle() {
        if (!this.selectedName) {
            return 'Grant access';
        }
        return (this.editingExisting ? 'Edit access — ' : 'Grant access — ') + this.selectedName;
    }
    get saveDisabled() {
        return this.busy || !this.selectedUserId;
    }
    get saveLabel() {
        return this.editingExisting ? 'Save access' : 'Assign access';
    }
    get roleOptions() {
        return [
            { value: 'Admin', label: 'Admin', selected: this.role === 'Admin', cls: this.role === 'Admin' ? 'role on' : 'role' },
            { value: 'Leader', label: 'Leader', selected: this.role === 'Leader', cls: this.role === 'Leader' ? 'role on' : 'role' },
            { value: ROLE_MEMBER, label: 'Team member', selected: this.role === ROLE_MEMBER, cls: this.role === ROLE_MEMBER ? 'role on' : 'role' }
        ];
    }

    handleSearchTerm(e) {
        this.searchTerm = e.target.value || '';
        this.queueSearch();
    }

    handleSearchKey() {
        this.queueSearch();
    }

    queueSearch() {
        window.clearTimeout(this.searchTimer);
        const term = (this.searchTerm || '').trim();
        if (term.length < 2) {
            this.hits = [];
            this.searched = false;
            return;
        }
        this.searchTimer = window.setTimeout(() => this.runSearch(term), 250);
    }

    runSearch(term) {
        searchUsers({ term })
            .then((rows) => {
                this.searched = true;
                this.hits = (rows || []).map((h) => ({
                    ...h,
                    meta: [h.profile, h.title, h.alreadyAssigned ? 'already has access' : '']
                        .filter(Boolean)
                        .join(' · ')
                }));
            })
            .catch((err) => {
                this.error = this.msg(err);
            });
    }

    pickHit(e) {
        const id = e.currentTarget.dataset.id;
        const hit = this.hits.find((h) => h.id === id);
        this.selectedUserId = id;
        this.selectedName = hit ? hit.name : '';
        this.hits = [];
        this.searched = false;
        this.loadGrant(id);
    }

    clearSelected() {
        this.selectedUserId = '';
        this.selectedName = '';
        this.editingExisting = false;
        this.role = ROLE_MEMBER;
        if (this.info) {
            this.tabItems = this.copyItems(this.info.tabCatalog);
            this.activityItems = this.copyItems(this.info.activityCatalog);
            this.info = this.decorate(this.info);
        }
    }

    cancelEdit() {
        this.clearSelected();
    }

    loadGrant(userId) {
        this.busy = true;
        this.error = undefined;
        getUserGrant({ userId })
            .then((g) => {
                this.applyGrant(g);
                this.editingExisting = !!g.existing;
                this.selectedName = g.name || this.selectedName;
            })
            .catch((err) => {
                this.error = this.msg(err);
            })
            .finally(() => {
                this.busy = false;
            });
    }

    applyGrant(g) {
        this.role = g.role || ROLE_MEMBER;
        this.tabItems = this.copyItems(g.tabs);
        this.activityItems = this.copyItems(g.activities);
        if (this.info) {
            this.info = this.decorate(this.info);
        }
    }

    handleRole(e) {
        const next = e.target.value;
        this.role = next;
        this.busy = true;
        rolePreset({ role: next })
            .then((g) => {
                this.tabItems = this.copyItems(g.tabs);
                this.activityItems = this.copyItems(g.activities);
            })
            .catch((err) => {
                this.error = this.msg(err);
            })
            .finally(() => {
                this.busy = false;
            });
    }

    toggleItem(e) {
        const kind = e.target.dataset.kind;
        const key = e.target.dataset.key;
        const checked = e.target.checked;
        const list = kind === 'tab' ? this.tabItems : this.activityItems;
        this.replaceItems(kind, list.map((i) => (i.key === key ? { ...i, checked } : i)));
    }

    replaceItems(kind, items) {
        if (kind === 'tab') {
            this.tabItems = items;
        } else {
            this.activityItems = items;
        }
    }

    selectedKeys(items) {
        return (items || []).filter((i) => i.checked).map((i) => i.key);
    }

    editUser(e) {
        const id = e.currentTarget.dataset.id;
        const row = this.info && this.info.users ? this.info.users.find((u) => u.id === id) : null;
        this.selectedUserId = id;
        this.selectedName = row ? row.name : '';
        this.editingExisting = true;
        this.loadGrant(id);
    }

    save() {
        if (!this.selectedUserId) {
            return;
        }
        const tabs = this.selectedKeys(this.tabItems);
        const activities = this.selectedKeys(this.activityItems);
        this.busy = true;
        this.error = undefined;
        this.notice = undefined;
        saveGrant({
            userId: this.selectedUserId,
            role: this.role,
            tabs,
            activities
        })
            .then(() => assignAppPermset({
                userId: this.selectedUserId,
                role: this.role,
                activities
            }))
            .then(() => {
                this.notice = this.editingExisting ? 'Access updated.' : 'Access granted.';
                this.clearSelected();
                return refreshApex(this.wired);
            })
            .catch((err) => {
                this.error = this.msg(err);
            })
            .finally(() => {
                this.busy = false;
            });
    }

    remove(e) {
        const id = e.currentTarget.dataset.id;
        this.busy = true;
        this.error = undefined;
        this.notice = undefined;
        revokeAppPermset({ userId: id })
            .then(() => deleteGrant({ userId: id }))
            .then(() => {
                if (this.selectedUserId === id) {
                    this.clearSelected();
                }
                this.notice = 'Access removed.';
                return refreshApex(this.wired);
            })
            .catch((err) => {
                this.error = this.msg(err);
            })
            .finally(() => {
                this.busy = false;
            });
    }
}
