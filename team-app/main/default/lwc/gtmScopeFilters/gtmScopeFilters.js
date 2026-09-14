import { LightningElement, api, wire } from 'lwc';
import getScopeOptions from '@salesforce/apex/CockpitAeController.getScopeOptions';

const STORE_KEY = 'gtmScopeFilters';
const TEAM_MINE = 'mine';
const TEAM_DIRECTOR = 'director';

export default class GtmScopeFilters extends LightningElement {
    @api directorId;
    @api teamMode = TEAM_MINE;
    @api productType = 'ALL';
    @api sizeBand = 'ALL';

    runningUserId;
    runningUserName;
    directorOptions = [];
    productOptions = [{ label: 'All products', value: 'ALL' }];
    sizeOptions = [
        { label: 'All sizes', value: 'ALL' },
        { label: 'Under $50k', value: 'UNDER_50K' },
        { label: '$50–150k', value: 'BAND_50_150K' },
        { label: '$150k+', value: 'OVER_150K' }
    ];
    directorName = '';
    ready = false;

    @wire(getScopeOptions)
    wiredOptions({ data, error }) {
        if (data) {
            this.runningUserId = data.runningUserId;
            this.runningUserName = data.runningUserName;
            this.directorOptions = [
                { label: 'My team', value: TEAM_MINE }
            ].concat((data.directors || []).map((d) => ({ label: d.name, value: d.userId })));
            this.productOptions = [{ label: 'All products', value: 'ALL' }].concat(
                (data.productTypes || []).map((v) => ({ label: v, value: v }))
            );
            this.restore();
            this.ready = true;
            this.emit(false);
        } else if (error) {
            this.ready = true;
        }
    }

    get teamValue() {
        return this.teamMode === TEAM_DIRECTOR && this.directorId ? this.directorId : TEAM_MINE;
    }

    get caption() {
        const who = this.teamMode === TEAM_DIRECTOR && this.directorName
            ? this.directorName
            : (this.runningUserName || 'your team');
        const product = this.productType && this.productType !== 'ALL' ? this.productType : 'All products';
        const size = this.sizeLabel(this.sizeBand);
        return 'Team of ' + who + ' · ' + product + ' · ' + size;
    }

    handleTeam(e) {
        const v = e.detail.value;
        if (v === TEAM_MINE) {
            this.teamMode = TEAM_MINE;
            this.directorId = this.runningUserId;
            this.directorName = this.runningUserName;
        } else {
            this.teamMode = TEAM_DIRECTOR;
            this.directorId = v;
            const hit = this.directorOptions.find((o) => o.value === v);
            this.directorName = hit ? hit.label : '';
        }
        this.persistAndEmit();
    }

    handleProduct(e) {
        this.productType = e.detail.value;
        this.persistAndEmit();
    }

    handleSize(e) {
        this.sizeBand = e.detail.value;
        this.persistAndEmit();
    }

    persistAndEmit() {
        this.persist();
        this.emit(true);
    }

    emit(userChanged) {
        const detail = {
            directorId: this.teamMode === TEAM_DIRECTOR ? this.directorId : this.runningUserId,
            teamMode: this.teamMode || TEAM_MINE,
            productType: this.productType || 'ALL',
            sizeBand: this.sizeBand || 'ALL',
            userChanged
        };
        this.dispatchEvent(new CustomEvent('scopechange', { detail }));
    }

    persist() {
        try {
            sessionStorage.setItem(STORE_KEY, JSON.stringify({
                directorId: this.directorId,
                teamMode: this.teamMode,
                productType: this.productType,
                sizeBand: this.sizeBand,
                directorName: this.directorName
            }));
        } catch (e) { /* session storage may be blocked */ }
    }

    restore() {
        try {
            const raw = sessionStorage.getItem(STORE_KEY);
            if (!raw) {
                this.teamMode = TEAM_MINE;
                this.directorId = this.runningUserId;
                this.directorName = this.runningUserName;
                return;
            }
            const saved = JSON.parse(raw);
            this.teamMode = saved.teamMode || TEAM_MINE;
            this.directorId = saved.directorId || this.runningUserId;
            this.productType = saved.productType || 'ALL';
            this.sizeBand = saved.sizeBand || 'ALL';
            this.directorName = saved.directorName || this.runningUserName;
        } catch (e) {
            this.teamMode = TEAM_MINE;
            this.directorId = this.runningUserId;
            this.directorName = this.runningUserName;
        }
    }

    sizeLabel(band) {
        const hit = this.sizeOptions.find((o) => o.value === band);
        return hit ? hit.label : 'All sizes';
    }
}
