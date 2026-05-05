import {
  AccessMap,
  IdentifierSetMultiMap,
  IdentifierStrategy,
  InternalServerError,
  ModesExtractor,
  Operation,
  ResourceIdentifier,
  ResourceSet
} from '@solid/community-server';
import { PERMISSIONS } from '@solidlab/policy-engine';

/**
 * Transforms the result of the wrapped {@link ModesExtractor} to only return modes for existing resources.
 * In case a non-existent resource requires the `create` access mode;
 * instead, this class will return the first existing parent container with the `create` access mode instead.
 * This is because UMA only has identifiers for existing resources,
 * so we let the server interpret the `create` permission as
 * "Is the user allowed to create resources in this container?".
 *
 * A disadvantage of this solution is that the server ignores other permissions on the non-existent resource.
 * This can be relevant if you have a server that needs to return 401/403 when accessing a resource that does not exist,
 * instead of a 404.
 */
export class ParentCreateExtractor extends ModesExtractor {
  public constructor(
    protected readonly source: ModesExtractor,
    protected readonly identifierStrategy: IdentifierStrategy,
    protected readonly resourceSet: ResourceSet,
  ) {
    super();
  }

  public async canHandle(input: Operation): Promise<void> {
    return this.source.canHandle(input);
  }

  public async handle(input: Operation): Promise<AccessMap> {
    const result = await this.source.handle(input);
    const updatedResult: AccessMap = new IdentifierSetMultiMap();
    for (const [ id, modes ] of result.entrySets()) {
      if (modes.has(PERMISSIONS.Create)) {
        const parent = await this.findFirstExistingParent(id);
        updatedResult.add(parent, PERMISSIONS.Create);
      } else {
        updatedResult.add(id, modes);
      }
    }
    return updatedResult;
  }

  protected async findFirstExistingParent(id: ResourceIdentifier): Promise<ResourceIdentifier> {
    const normalizedId = normalizeIdentifier(id);
    if (await this.resourceSet.hasResource(normalizedId)) {
      return normalizedId;
    }
    if (this.identifierStrategy.isRootContainer(normalizedId)) {
      throw new InternalServerError(`Root container ${normalizedId.path} does not exist`);
    }
    return this.findFirstExistingParent(normalizeIdentifier(this.identifierStrategy.getParentContainer(normalizedId)));
  }
}

function normalizeIdentifier(id: ResourceIdentifier): ResourceIdentifier {
  const url = new URL(id.path);
  const normalizedSegments: string[] = [];
  for (const segment of url.pathname.split('/')) {
    const decoded = decodeURIComponent(segment);
    if (!decoded || decoded === '.') {
      continue;
    }
    if (decoded === '..') {
      normalizedSegments.pop();
      continue;
    }
    normalizedSegments.push(segment);
  }
  url.pathname = `/${normalizedSegments.join('/')}${url.pathname.endsWith('/') ? '/' : ''}`;
  return { ...id, path: url.href };
}
