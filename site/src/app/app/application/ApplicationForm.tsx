"use client";

import { APPLICATION_DISCOVERY_SOURCES } from "@prisma-eco/contracts";
import { MinecraftNicknameAutocomplete } from "@/components/MinecraftNicknameAutocomplete";
import {
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  FormField,
  Input,
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
  Textarea,
} from "@prisma-eco/ui";

export function ApplicationForm({
  defaults,
}: {
  defaults: {
    fullName: string;
    birthDate: string;
    nickname: string;
    platform: "JAVA" | "BEDROCK";
    goal?: string;
    about?: string;
    discoverySource?: string;
  };
}) {
  const today = new Date();
  const maxBirthDateDate = new Date(
    today.getFullYear() - 14,
    today.getMonth(),
    today.getDate(),
  );
  // Date inputs represent local calendar dates. Avoid toISOString(), which
  // converts local midnight to UTC and can shift the allowed date by one day.
  const maxBirthDate = [
    maxBirthDateDate.getFullYear(),
    String(maxBirthDateDate.getMonth() + 1).padStart(2, "0"),
    String(maxBirthDateDate.getDate()).padStart(2, "0"),
  ].join("-");

  return (
    <form action="/api/applications" method="post" className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Основная информация</CardTitle>
          <p className="text-sm text-muted-foreground">
            Заполните данные один раз — сайт и Telegram используют один и тот же workflow заявки.
          </p>
        </CardHeader>

        <CardContent className="grid gap-5 md:grid-cols-2">
          <FormField label="Имя" required description="От 2 до 100 символов.">
            <Input
              name="full_name"
              required
              minLength={2}
              maxLength={100}
              autoComplete="name"
              defaultValue={defaults.fullName}
            />
          </FormField>

          <FormField label="Дата рождения" required description="Минимальный возраст для подачи — 14 лет.">
            <Input
              name="birth_date"
              type="date"
              required
              max={maxBirthDate}
              defaultValue={defaults.birthDate}
            />
          </FormField>

          <FormField label="Minecraft-ник" required description="Java: 3–16 символов. Bedrock: Gamertag как в Xbox, пробелы можно (например, D1lan ok) — на сервере он станет .D1lan_ok.">
            <MinecraftNicknameAutocomplete
              name="nickname"
              required
              minLength={3}
              maxLength={24}
              pattern="\.?[A-Za-z0-9_ ]+(#[0-9]{1,6})?"
              autoComplete="off"
              defaultValue={defaults.nickname}
            />
          </FormField>

          <FormField label="Платформа" required>
            <Select name="platform" defaultValue={defaults.platform} required>
              <SelectTrigger className="w-full">
                <SelectValue placeholder="Выберите платформу" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="JAVA">Java</SelectItem>
                <SelectItem value="BEDROCK">Bedrock</SelectItem>
              </SelectContent>
            </Select>
          </FormField>

          <div className="md:col-span-2">
            <FormField label="Откуда вы узнали о PRISMA?" required>
              <Select
                name="discovery_source"
                required
                defaultValue={defaults.discoverySource || undefined}
              >
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Выберите вариант" />
                </SelectTrigger>
                <SelectContent>
                  {APPLICATION_DISCOVERY_SOURCES.map((source) => (
                    <SelectItem key={source} value={source}>{source}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </FormField>
          </div>

          <div className="md:col-span-2">
            <FormField label="Что хотите делать на сервере?" description="Необязательно, до 1000 символов.">
              <Textarea
                name="goal"
                maxLength={1000}
                defaultValue={defaults.goal || ""}
                placeholder="Например: строить города, участвовать в событиях, играть с друзьями."
              />
            </FormField>
          </div>

          <div className="md:col-span-2">
            <FormField label="Расскажите о себе" description="Необязательно, до 1000 символов.">
              <Textarea
                name="about"
                maxLength={1000}
                defaultValue={defaults.about || ""}
                placeholder="Коротко о себе и своём опыте в Minecraft."
              />
            </FormField>
          </div>

          <div className="prisma-glass-surface md:col-span-2 rounded-lg border p-3">
            <label className="flex items-start gap-3 text-sm leading-5">
              <input
                type="checkbox"
                name="agreement"
                value="yes"
                required
                className="mt-1 size-4 rounded border-input"
              />
              <span>
                Я согласен на обработку данных, необходимых для работы PRISMA и рассмотрения заявки.
              </span>
            </label>
          </div>
        </CardContent>
      </Card>

      <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
        <Button type="submit" size="lg">
          Отправить заявку
        </Button>
      </div>
    </form>
  );
}
