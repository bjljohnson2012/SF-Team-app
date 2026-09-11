import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getAccessMatrix from '@salesforce/apex/CockpitForecastController.getAccessMatrix';
import assignAccess from '@salesforce/apex/CockpitForecastController.assignAccess';
import revokeAccess from '@salesforce/apex/CockpitForecastController.revokeAccess';

export default class SalesPerfAdmin extends LightningElement {
    wired;
    info;
    error;
    notice;
    selectedUserId = '';
    busy = false;

    @wire(getAccessMatrix)
    wire(result) {
        this.wired = result;
        if (result.data) { this.info = result.data; this.error = undefined; }
        else if (result.error) { this.error = this.msg(result.error); }
    }

    msg(e) { return (e && e.body && e.body.message) || 'Something went wrong.'; }
    get permSetName() { return (this.info && this.info.permSet) || ''; }
    get hasUsers() { return this.info && this.info.users && this.info.users.length > 0; }
    get userCount() { return this.hasUsers ? this.info.users.length : 0; }
    get canManage() { return !!(this.info && this.info.canManage); }
    get editBadge() { return this.info && this.info.editInCall ? 'granted' : 'denied'; }
    get overrideBadge() { return this.info && this.info.overrideClass ? 'granted' : 'denied'; }
    get apexBadge() { return this.info && this.info.apexAccess ? 'granted' : 'denied'; }
    get editClass() { return 'pill ' + (this.info && this.info.editInCall ? 'p-hi' : 'p-ex'); }
    get overrideClass() { return 'pill ' + (this.info && this.info.overrideClass ? 'p-hi' : 'p-ex'); }
    get apexClass() { return 'pill ' + (this.info && this.info.apexAccess ? 'p-hi' : 'p-ex'); }

    get assignableOptions() {
        const a = (this.info && this.info.assignable) || [];
        return a.map((u) => ({ id: u.id, label: u.name + (u.profile ? ' \u2014 ' + u.profile : '') }));
    }
    get hasAssignable() { return this.assignableOptions.length > 0; }
    get assignDisabled() { return this.busy || !this.selectedUserId; }

    handleSelect(e) { this.selectedUserId = e.target.value; }

    assign() {
        if (!this.selectedUserId) return;
        this.busy = true; this.error = undefined; this.notice = undefined;
        assignAccess({ userId: this.selectedUserId })
            .then(() => { this.notice = 'Access granted.'; this.selectedUserId = ''; return refreshApex(this.wired); })
            .catch((err) => { this.error = this.msg(err); })
            .finally(() => { this.busy = false; });
    }

    remove(e) {
        const id = e.currentTarget.dataset.id;
        this.busy = true; this.error = undefined; this.notice = undefined;
        revokeAccess({ userId: id })
            .then(() => { this.notice = 'Access removed.'; return refreshApex(this.wired); })
            .catch((err) => { this.error = this.msg(err); })
            .finally(() => { this.busy = false; });
    }
}
