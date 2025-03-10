import { getLoggerFor } from "@solid/community-server";
import { DialogInput, Permission, Ticket } from "../..";
import { ContractStorage } from "./ContractStorage";
import { ODRLContract, ODRLConstraint, ODRLPermission } from "../../views/Contract";
import { randomUUID } from "crypto";
import { ReversePermissionMapping } from "../../util/rdf/RequestProcessing";

export class ContractManager {
    private readonly logger = getLoggerFor(this);
    storage: ContractStorage = new ContractStorage();

    /**
     * Finds an existing contract for the given ticket.
     * @param input Ticket containing the WebID and requested permissions.
     * @returns Matched ODRLContract or undefined if no valid contract is found.
     */
    findContract(input: Ticket): ODRLContract | undefined {
        const identifier = input.provided["urn:solidlab:uma:claims:types:webid"] as string | undefined;
        if (!identifier) return;
        
        if (input.permissions.length !== 1) {
            this.logger.debug("Cannot process multiple permission requests with current policy setup");
            return;
        }

        // TODO: Handle multiple permission requirements in the same request
        // TODO: Check if contract requirements are still valid

        return this.storage.matchContract(input.permissions[0], identifier);
    }

    /**
     * Creates a new ODRL contract dynamically.
     * @param perms List of permissions to include in the contract.
     * @param options Configuration for contract assigner, assignee, description, and constraints.
     * @returns Generated ODRLContract.
     */
    createContract(perms: Permission[], options: {
        assigner: string,
        assignee: string,
        description?: string,
        constraints?: ODRLConstraint[]
    }): ODRLContract {
        this.logger.debug("Creating Contract");

        if (perms.length === 0) {
            throw new Error("Cannot create a contract with no permissions.");
        }

        const permissions: ODRLPermission[] = perms.map(permission => ({
            "@type": "Permission",
            action: ReversePermissionMapping[permission.resource_scopes[0]],
            target: permission.resource_id,
            assigner: options.assigner,
            assignee: options.assignee,
            constraint: options.constraints ?? [] // Use provided constraints or an empty list
        }));

        return {
            "@context": "http://www.w3.org/ns/odrl.jsonld",
            "@type": "Agreement",
            uid: `urn:uma:pacsoi:agreement:${randomUUID()}`,
            "http://purl.org/dc/terms/description": options.description ?? "Generic data processing agreement.",
            "https://w3id.org/dpv#hasLegalBasis": { "@id": "https://w3id.org/dpv/legal/eu/gdpr#eu-gdpr:A9-2-a" },
            permission: permissions
        };
    }
}

/**
 * Helper function to generate a date one week from today.
 * @returns Date object representing next week.
 */
function nextweek(): Date {
    const today = new Date();
    return new Date(today.getFullYear(), today.getMonth(), today.getDate() + 7);
}
