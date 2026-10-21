Implemente neste repositório um projeto de portfólio para proteger um Application Load Balancer existente com AWS WAFv2, usando Terraform.



Antes de alterar arquivos, inspecione o repositório e siga a estrutura, as convenções e as ferramentas que já existirem. Se o repositório estiver vazio, crie uma estrutura clara, documentada e fácil de manter. Não faça deploy nem acesse uma conta AWS.



\## Objetivo e limites



Criar o Web ACL e associá-lo a um ALB existente. O projeto não deve criar ou alterar ALB, VPC, listeners, target groups, aplicação ou DNS.



A pessoa que executar o projeto deve informar explicitamente o ARN do ALB. Não descubra ou escolha o ALB automaticamente. Receba o ARN como variável do Terraform, variável do GitLab e parâmetro do Jenkins. Valide o formato e documente que o ALB e o Web ACL precisam estar na mesma região.



Este é um projeto público independente. Não copie código, regras, nomes, domínios, IDs, configurações ou informações proprietárias da SoftExpert, nem apresente o projeto como se fosse a implementação real de uma empresa.



\## Infraestrutura Terraform



Implemente AWS WAFv2 Regional associado ao ALB informado, incluindo:



\- Web ACL com ação padrão configurável;

\- AWS Managed Rules Common Rule Set e Known Bad Inputs;

\- rate limit por IP, com limite configurável;

\- listas opcionais de IPs permitidos e bloqueados;

\- bloqueio geográfico opcional e configurável;

\- métricas, sampled requests e logs do WAF;

\- envio dos logs para S3 usando Amazon Data Firehose.



As regras devem iniciar em modo `COUNT`. Documente como observar métricas e logs, investigar falsos positivos e promover as regras para `BLOCK`. Uma mudança para `BLOCK` deve exigir novo plano e nova aprovação.



Use recursos e variáveis organizados, nomes claros, valores fictícios nos exemplos e um `.gitignore` adequado. Não versione credenciais, arquivos de estado, arquivos de plano nem variáveis locais. Documente a configuração de um backend remoto seguro para o estado, com criptografia, versionamento e locking.



Athena, Glue, CloudFront/WAF global, CAPTCHA, Bot Control, multi-região, multi-conta e criação do ALB ficam fora do MVP.



\## Pipelines



Crie duas pipelines independentes:



1\. GitLab CI/CD.

2\. Jenkins Pipeline.



Ambas devem validar e gerar um `terraform plan`, exigir aprovação humana obrigatória depois do plano e só então executar `terraform apply`. O apply deve usar exatamente o arquivo binário do plano aprovado. Não gere um novo plano depois da aprovação e não permita apply automático.



\### GitLab CI/CD



\- Crie a configuração da pipeline no arquivo convencional do GitLab.

\- Execute formatação e validação em branches e merge requests.

\- Restrinja plan e apply de implantação à branch padrão protegida.

\- Disponibilize o plano como artefato temporário, com acesso restrito.

\- Insira uma etapa manual de aprovação após o plan.

\- Faça o apply depender tanto do plano quanto da aprovação.

\- Use environment protegido quando disponível.

\- Receba o ARN do ALB por variável protegida.

\- Use OIDC e credenciais temporárias da AWS, sem access keys estáticas.



\### Jenkins



\- Crie um `Jenkinsfile` declarativo.

\- Defina parâmetros para região AWS e ARN do ALB existente.

\- Inclua os estágios Validate, Plan, Approval e Apply, nessa ordem.

\- Restrinja a implantação à branch padrão protegida.

\- Use uma pausa manual de aprovação após o plan, limitada a usuário ou grupo autorizado.

\- Preserve o mesmo arquivo de plano entre os estágios Plan e Apply.

\- Use credenciais temporárias associadas a uma role IAM, sem credenciais AWS no repositório.



\## Segurança e operação



\- Documente as permissões IAM de privilégio mínimo e as configurações de OIDC/federação.

\- Proteja branches, environments, artefatos do plano, workspace do Jenkins e estado do Terraform.

\- Restrinja os logs de pipeline para não revelar tokens ou credenciais.

\- Proteja o destino S3 dos logs com criptografia, controle de acesso e política de retenção.

\- Documente implantação inicial em `COUNT`, revisão, promoção para `BLOCK`, troubleshooting e rollback.

\- Não aplique mudanças em produção nem execute comandos que alterem recursos AWS.



\## Documentação e verificação



Crie um README com propósito, diagrama de arquitetura, pré-requisitos, parâmetros, configuração do backend, permissões IAM, uso local, uso das duas pipelines, aprovação manual, operação das regras, logging, troubleshooting, custos, limpeza e limitações.



Adicione validações automatizadas relevantes, sem inventar credenciais ou valores reais. Execute os testes locais disponíveis, como formatação e validação do Terraform e parsing das configurações das pipelines. Informe claramente qualquer verificação que não puder ser executada.



\## Critérios de aceite



\- O ARN do ALB existente é obrigatório e indicado explicitamente por quem executa.

\- Terraform não cria nem modifica o ALB.

\- O Web ACL Regional é associado somente ao ARN fornecido.

\- Regras começam em `COUNT`.

\- Logs seguem para S3 via Data Firehose.

\- GitLab CI/CD e Jenkins têm pipelines próprias.

\- Em ambas, a aprovação acontece depois do plan e antes do apply.

\- Ambas aplicam o mesmo plano aprovado, sem gerar outro plano nesse intervalo.

\- Não há apply automático nem deploy realizado durante esta tarefa.

\- A documentação deixa claros os requisitos de segurança e os limites do projeto.

