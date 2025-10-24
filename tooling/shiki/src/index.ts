import type { LanguageRegistration } from 'shiki';
import grammar from '@ferrule/grammar';

export const ferruleLanguage: LanguageRegistration = {
  ...grammar,
  name: 'ferrule',
  aliases: ['fe'],
};

export default ferruleLanguage;

