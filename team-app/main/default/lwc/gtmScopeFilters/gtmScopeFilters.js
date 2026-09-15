import { LightningElement, api } from 'lwc';
import getFilterOptions from '@salesforce/apex/CockpitWinRateController.getFilterOptions';

const STORE = 'gtmScopeFilters';
const STORE_GROUPED = 'gtmScopeFiltersGrouped';

export default class GtmScopeFilters extends LightningElement {
    @api groupedProducts = false;
    directorId = '';
    teamMode = 'my';
    productType = 'ALL';
    sizeBand = 'ALL';
    directors = [];
    productTypes = [];
    sizeBands = [];
    defaultDirectorName = '';
    ready = false;
    error;

    connectedCallback() {
        const saved = this.readStore();
        getFilterOptions()
            .then((o) => {
                this.directors = this.withKeys(o.directors || []);
                const products = this.groupedProducts
                    ? (o.productGroups || o.productTypes)
                    : o.productTypes;
                this.productTypes = this.withKeys(products || []);
                this.sizeBands = this.withKeys(o.sizeBands || []);
                this.defaultDirectorName = o.defaultDirectorName;
                if (saved) {
                    this.directorId = saved.directorId || '';
                    this.teamMode = saved.teamMode || 'my';
                    this.productType = saved.productType || (this.groupedProducts ? this.defaultProduct() : 'ALL');
                    this.sizeBand = saved.sizeBand || 'ALL';
                }
                const known = new Set((this.productTypes || []).map((p) => p.value));
                if (this.groupedProducts && !known.has(this.productType)) {
                    this.productType = this.defaultProduct();
                }
                this.ready = true;
                this.emit();
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || e.message || 'Could not load filters.';
            });
    }

    get scopeCaption() {
        const dir = this.teamMode === 'my' || !this.directorId
            ? (this.defaultDirectorName || 'My team')
            : this.directorLabel(this.directorId);
        return `Team of ${dir} · ${this.productLabel(this.productType)} · ${this.sizeLabel(this.sizeBand)}`;
    }

    handleDirector(e) {
        this.directorId = e.target.value;
        this.teamMode = this.directorId ? 'director' : 'my';
        this.persistAndEmit();
    }
    handleProduct(e) {
        this.productType = e.target.value;
        this.persistAndEmit();
    }
    handleSize(e) {
        this.sizeBand = e.target.value;
        this.persistAndEmit();
    }

    persistAndEmit() {
        this.writeStore();
        this.emit();
    }

    emit() {
        const detail = {
            directorId: this.directorId || null,
            teamMode: this.teamMode,
            productType: this.productType,
            sizeBand: this.sizeBand
        };
        this.dispatchEvent(new CustomEvent('scopechange', { detail }));
    }

    withKeys(rows) {
        return (rows || []).map((r) => ({
            value: r.value,
            label: r.label,
            key: r.value ? r.value : 'my'
        }));
    }

    directorLabel(id) {
        const hit = (this.directors || []).find((d) => d.value === id);
        return hit ? hit.label : 'Selected director';
    }
    storeKey() {
        return this.groupedProducts ? STORE_GROUPED : STORE;
    }

    defaultProduct() {
        if (!this.groupedProducts) return 'ALL';
        const first = (this.productTypes || [])[0];
        return first && first.value ? first.value : 'BUDGET';
    }

    productLabel(v) {
        const hit = (this.productTypes || []).find((d) => d.value === v);
        return hit ? hit.label : (this.groupedProducts ? 'Budget' : 'All products');
    }
    sizeLabel(v) {
        const hit = (this.sizeBands || []).find((d) => d.value === v);
        return hit ? hit.label : 'All sizes';
    }

    readStore() {
        try {
            const raw = sessionStorage.getItem(this.storeKey());
            return raw ? JSON.parse(raw) : null;
        } catch (e) {
            return null;
        }
    }
    writeStore() {
        try {
            sessionStorage.setItem(this.storeKey(), JSON.stringify({
                directorId: this.directorId,
                teamMode: this.teamMode,
                productType: this.productType,
                sizeBand: this.sizeBand
            }));
        } catch (e) { /* private mode */ }
    }
}
