import { LightningElement, wire } from 'lwc';
import getAccessMatrix from '@salesforce/apex/CockpitForecastController.getAccessMatrix';

export default class SalesPerfAdmin extends LightningElement {
    info;
    error;

    @wire(getAccessMatrix)
    wired({ data, error }) {
        if (data) { this.info = data; this.error = undefined; }
        else if (error) { this.error = (error.body && error.body.message) || 'Could not load access.'; }
    }

    get hasUsers() { return this.info && this.info.users && this.info.users.length > 0; }
    get userCount() { return this.hasUsers ? this.info.users.length : 0; }
    get editBadge() { return this.info && this.info.editInCall ? 'granted' : 'denied'; }
    get overrideBadge() { return this.info && this.info.overrideClass ? 'granted' : 'denied'; }
    get apexBadge() { return this.info && this.info.apexAccess ? 'granted' : 'denied'; }
    get editClass() { return 'pill ' + (this.info && this.info.editInCall ? 'p-hi' : 'p-ex'); }
    get overrideClass() { return 'pill ' + (this.info && this.info.overrideClass ? 'p-hi' : 'p-ex'); }
    get apexClass() { return 'pill ' + (this.info && this.info.apexAccess ? 'p-hi' : 'p-ex'); }
}
