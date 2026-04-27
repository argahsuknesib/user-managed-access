import type { AccessMap, AuthorizerInput } from '@solid/community-server';
import {
  Authorizer,
  createErrorMessage,
  ForbiddenHttpError,
  InternalServerError,
  UnauthorizedHttpError,
  NotFoundHttpError
} from '@solid/community-server';
import { getLoggerFor } from 'global-logger-factory';
import { DataFactory } from 'n3';
import { UmaClient } from '../uma/UmaClient';
import { OwnerUtil } from '../util/OwnerUtil';

const { namedNode, literal } = DataFactory;

export const WWW_AUTH = namedNode('urn:css:http:headers:www-authenticate');

function describeError(error: unknown): string {
  if (error instanceof Error) {
    return error.message || error.name || error.stack || 'Unknown error';
  }

  const message = createErrorMessage(error as Error);
  return message || 'Unknown error';
}

function isLikelyPatFailure(message: string): boolean {
  return /Unable to generate PAT|PAT registration failed|token_endpoint|client_credentials/i.test(message);
}

function isLikelyRegistrationFailure(message: string): boolean {
  return /no UMA ID found|stale MemoryMapStorage|not registered with UMA AS|re-run script:setup-alice-derived/i.test(message);
}

/**
 * Authorizer that bases its decision on that of another Authorizer.
 * It discovers the relevant UMA Authorization Server for the requested resource(s),
 * and checks whether that server protects the resource or whether it is public.
 * If the resource is not public and access is not granted by the other Authorizer,
 * the UmaAuthorizer includes an UMA Permission Ticket in the resulting error.
 */
export class UmaAuthorizer extends Authorizer {
  protected readonly logger = getLoggerFor(this);

  /**
   * The UmaAuthorizer bases its decisions on those of another {@link Authorizer}.
   * It uses an {@link OwnerUtil} to retrieve the relevant UMA issuer,
   * and an {@link UmaClient} to communicate with that issuer.
   * @param authorizer - {@link Authorizer} that makes the main decision.
   * @param ownerUtil - {@link OwnerUtil} that links resources to owners and issuers.
   * @param umaClient - {@link UmaClient} that communicates with UMA issuers.
   */
  public constructor(
    protected authorizer: Authorizer,
    protected ownerUtil: OwnerUtil,
    protected umaClient: UmaClient,
  ) {
    super();
  }

  public async handle(input: AuthorizerInput): Promise<void> {
    try {

      // Try authorizer
      await this.authorizer.handleSafe(input);
    } catch (error: unknown) {

      // Unless 401/403 throw original error
      if (!UnauthorizedHttpError.isInstance(error) && !ForbiddenHttpError.isInstance(error)) throw error;

      // Request UMA ticket
      const authHeader = await this.requestTicket(input.requestedModes);

      // Add auth header to error metadata if private
      if (authHeader) {
        error.metadata.add(WWW_AUTH, literal(authHeader));
        this.logger.info(`Authorization failed: ${createErrorMessage(error)}`);
        throw error;
      }

      // Return if public
      this.logger.info(`Authorization succeeded: resource is public.`);
    }
  }

  protected async requestTicket(requestedModes: AccessMap): Promise<string | undefined> {
    const owner = await this.ownerUtil.findCommonOwner(requestedModes.keys());
    const { issuer, credentials } = await this.ownerUtil.findUmaSettings(owner);

    if (!issuer || !credentials) throw new InternalServerError(`Credentials and/or issuer are not set for ${owner}.`);

    const targetPaths = Array.from(requestedModes.keys()).map((id) => id.path).join(', ');

    try {
      const ticket = await this.umaClient.fetchTicket(requestedModes, issuer, credentials);
      return ticket ? `UMA realm="solid", as_uri="${issuer}", ticket="${ticket}"` : undefined;
    } catch (e) {
      if (NotFoundHttpError.isInstance(e)) {
        throw e;
      }

      const causeMessage = describeError(e).trim();
      const patAcquisitionFailed = isLikelyPatFailure(causeMessage);
      const registrationMissing = isLikelyRegistrationFailure(causeMessage);
      const contextMessage = [
        `resource(s)=[${targetPaths}]`,
        `issuer=${issuer}`,
        `patAcquisitionFailed=${patAcquisitionFailed}`,
        `resourceRegistrationMissing=${registrationMissing}`,
        `cause=${causeMessage}`,
      ].join(' | ');

      this.logger.error(`Error while requesting UMA header: ${contextMessage}`);
      throw new InternalServerError(`Error while requesting UMA header: ${contextMessage}`);
    }
  }
}
