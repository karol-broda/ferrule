import type { LanguageRegistration } from 'shiki';
import grammar from '@ferrule/grammar' with {type: 'json'};

export const ferruleLanguage: LanguageRegistration = {
  ...grammar,
  name: 'ferrule',
  aliases: ['fe'],
};

export default ferruleLanguage;

